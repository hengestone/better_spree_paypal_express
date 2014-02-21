require 'spec_helper'

describe Spree::Gateway::PayPalExpress do
  let(:gateway) { Spree::Gateway::PayPalExpress.create!(name: "PayPalExpress", :environment => Rails.env) }

  context "payment purchase" do
    let(:payment) do
      payment = FactoryGirl.create(:payment, :payment_method => gateway, :amount => 10)
      payment.stub :source => mock_model(Spree::PaypalExpressCheckout, :token => 'fake_token', :payer_id => 'fake_payer_id', :update_column => true)
      payment
    end

    let(:provider) do
      provider = double('Provider')
      gateway.stub(:provider => provider)
      provider
    end

    before do
      provider.should_receive(:build_get_express_checkout_details).with({
        :Token => 'fake_token'
      }).and_return(pp_details_request = double)

      pp_details_response = double(:get_express_checkout_details_response_details =>
        double(:PaymentDetails => {
          :OrderTotal => {
            :currencyID => "USD",
            :value => "10.00"
          }
        }))

      provider.should_receive(:get_express_checkout_details).
        with(pp_details_request).
        and_return(pp_details_response)

      provider.should_receive(:build_do_express_checkout_payment).with({
        :DoExpressCheckoutPaymentRequestDetails => {
          :PaymentAction => "Sale",
          :Token => "fake_token",
          :PayerID => "fake_payer_id",
          :PaymentDetails => pp_details_response.get_express_checkout_details_response_details.PaymentDetails
        }
      })
    end

    # Test for #11
    it "succeeds" do
      response = double('pp_response', :success? => true)
      response.stub_chain("do_express_checkout_payment_response_details.payment_info.first.transaction_id").and_return '12345'
      provider.should_receive(:do_express_checkout_payment).and_return(response)
      lambda { payment.purchase! }.should_not raise_error
    end

    # Test for #4
    it "fails" do
      response = double('pp_response', :success? => false,
                          :errors => [double('pp_response_error', :long_message => "An error goes here.")])
      provider.should_receive(:do_express_checkout_payment).and_return(response)
      lambda { payment.purchase! }.should raise_error(Spree::Core::GatewayError, "An error goes here.")
    end

    
  end

  context "Canceling an order" do
    describe "crediting an account via cancel" do
      let(:source){ double(transaction_id: "ABC123") }
      let(:order){ FactoryGirl.create(:order, tax_total: BigDecimal.new("0"), payment_total: BigDecimal.new("3000"), adjustment_total: BigDecimal.new("500"), item_total: BigDecimal.new('2500'), total: BigDecimal.new('3000')) }
      let(:payment) do 
        pmt = order.payments.create(amount: BigDecimal.new('3000'))
        pmt.source = Spree::PaypalExpressCheckout.create!(:transaction_id => 'abc123', :token => 'fake_token', :payer_id => 'fake_payer_id')
        pmt.save!
        pmt
      end

      let(:amount){ 0 } # when cancelling via spree admin dashboard, credit!(nil) is called. effectively zero for the refund_amount
      let(:response_code){ nil }
      let(:gateway_options) do
        {
          :email => "me@example.com",
          :customer => "me@example.com",
          :customer_id => 1,
          :ip => "127.0.0.1",
          :order_id => "#{order.number}-#{payment.identifier}",
          :shipping =>  order.adjustment_total,
          :tax => order.tax_total,
          :subtotal =>  order.item_total,
          :discount =>  BigDecimal.new("0"),
          :currency => "USD",
          :billing_address => nil,
          :shipping_address =>  {
            :name => "Cali Bob",
            :address1 => "555 Rock Ridge Road",
            :address2 => "",
            :city => "Los Angeles",
            :state => "CA",
            :zip => "90210",
            :country => "US",
            :phone => "555 555 5555"
          }
        }
      end

      it "successfully cancels an order" do
        described_class.any_instance.should_receive(:refund).with(payment, order.total)
        paypal = described_class.new
        paypal.credit(amount, response_code, gateway_options)
      end
    end
  end

end
