module Spree
  class PaypalController < StoreController
    def express
      items = user_order.line_items.map(&method(:line_item))
      tax_adjustments = user_order.all_adjustments.tax.additional
      shipping_adjustments = user_order.all_adjustments.shipping
      user_order.all_adjustments.eligible.each do |adjustment|
        next if (tax_adjustments + shipping_adjustments).include?(adjustment)
        items << {
          :Name => adjustment.label,
          :Quantity => 1,
          :Amount => {
            :currencyID => user_order.currency,
            :value => adjustment.amount
          }
        }
      end

      # Because PayPal doesn't accept $0 items at all.
      # See #10
      # https://cms.paypal.com/uk/cgi-bin/?cmd=_render-content&content_ID=developer/e_howto_api_ECCustomizing
      # "It can be a positive or negative value but not zero."
      items.reject!{|item| item[:Amount][:value].zero? }
      pp_request = provider.build_set_express_checkout(express_checkout_request_details(user_order, items))

      begin
        pp_response = provider.set_express_checkout(pp_request)
        if pp_response.success?
          redirect_to provider.express_checkout_url(pp_response, useraction: 'commit')
        else
          flash[:error] = Spree.t('flash.generic_error', scope: 'paypal', reasons: pp_response.errors.map(&:long_message).join(" "))
          redirect_to paypal_error_path(user_order)
        end
      rescue SocketError
        flash[:error] = Spree.t('flash.connection_failed', scope: 'paypal')
        redirect_to paypal_error_path(user_order)
      end
    end

    def confirm
      user_order.payments.create!({
        source: Spree::PaypalExpressCheckout.create({
          token: params[:token],
          payer_id: params[:PayerID]
        }),
        amount: user_order.total,
        payment_method: payment_method
      })
      user_order.next
      user_order.next if user_order.confirm?
      if user_order.complete?
        flash.notice = Spree.t(:user_order_processed_successfully)
        flash[:commerce_tracking] = "nothing special"
        redirect_to completion_route(user_order)
      else
        redirect_to paypal_error_path(user_order)
      end
    end

    def cancel
      flash[:notice] = Spree.t('flash.cancel', scope: 'paypal')
      redirect_to after_cancel_path
    end

    private

    def paypal_success_path
      checkout_state_path(:payment)
    end

    def paypal_error_path(user_order)
      checkout_state_path(user_order.state)
    end

    def after_cancel_path
      checkout_state_path(user_order.state)
    end

    def line_item(item)
      {
          :Name => item.product.name,
          :Number => item.variant.sku,
          :Quantity => item.quantity,
          :Amount => {
              :currencyID => item.order.currency,
              :value => item.price
          },
          :ItemCategory => "Physical"
      }
    end

    def express_checkout_request_details(user_order, items)
      { :SetExpressCheckoutRequestDetails => {
          :InvoiceID => user_order.number,
          :ReturnURL => confirm_paypal_url(:payment_method_id => params[:payment_method_id], :utm_nooverride => 1),
          :CancelURL =>  cancel_paypal_url,
          :SolutionType => payment_method.preferred_solution.present? ? payment_method.preferred_solution : "Mark",
          :LandingPage => payment_method.preferred_landing_page.present? ? payment_method.preferred_landing_page : "Billing",
          :cppheaderimage => payment_method.preferred_logourl.present? ? payment_method.preferred_logourl : "",
          :PaymentDetails => [payment_details(items)]
      }}
    end

    def payment_method
      Spree::PaymentMethod.find(params[:payment_method_id])
    end

    def provider
      payment_method.provider
    end

    def payment_details(items)
      # item_sum = items.sum { |i| i[:Quantity] * i[:Amount][:value] }

      # This retrieves the cost of shipping after promotions are applied
      # For example, if shippng costs $10, and is free with a promotion, shipment_sum is now $10
      shipment_sum = user_order.shipments.map(&:discounted_cost).sum

      # This calculates the item sum based upon what is in the user_order total, but not for shipping
      # or tax.  This is the easiest way to determine what the items should cost, as that
      # functionality doesn't currently exist in Spree core
      item_sum = user_order.total - shipment_sum - user_order.additional_tax_total

      if item_sum.zero?
        # Paypal does not support no items or a zero dollar ItemTotal
        # This results in the user_order summary being simply "Current purchase"
        {
          :OrderTotal => {
            :currencyID => user_order.currency,
            :value => user_order.total
          }
        }
      else
        {
          :OrderTotal => {
            :currencyID => user_order.currency,
            :value => user_order.total
          },
          :ItemTotal => {
            :currencyID => user_order.currency,
            :value => item_sum
          },
          :ShippingTotal => {
            :currencyID => user_order.currency,
            :value => user_order.ship_total
          },
          :TaxTotal => {
            :currencyID => user_order.currency,
            :value => user_order.additional_tax_total
          },
          :ShipToAddress => address_options,
          :PaymentDetailsItem => items,
          :ShippingMethod => "Shipping Method Name Goes Here",
          :PaymentAction => "Sale"
        }
      end
    end

    def address_options
      {
        :Name => user_order.ship_address.try(:full_name),
        :Street1 => user_order.ship_address.address1,
        :Street2 => user_order.ship_address.address2,
        :CityName => user_order.ship_address.city,
        :StateOrProvince => user_order.ship_address.state_text,
        :Country => user_order.ship_address.country.iso,
        :PostalCode => user_order.ship_address.zipcode
      }
    end

    def completion_route(user_order)
      user_order_path(user_order, token: user_order.token)
    end

    def user_order
      @_user_order ||= current_order || current_user.orders.incomplete.user_order(updated_at: :desc).first || raise(ActiveRecord::RecordNotFound)
    end
  end
end
