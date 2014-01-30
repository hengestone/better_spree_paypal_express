//= require admin/spree_backend

SpreePaypalExpress = {
  hideSettings: function(paymentMethod) {
    if (SpreePaypalExpress.paymentMethodID && paymentMethod.val() == SpreePaypalExpress.paymentMethodID) {
      $('.payment-method-settings').children().hide();
	  $('#payment_amount').prop('disabled', true);
	  $('button[type="submit"]').prop('disabled', true);
      $('#paypal-warning').show();
    } else if (SpreePaypalExpress.paymentMethodID) {
      $('.payment-method-settings').children().show();
	  $('button[type=submit]').prop('disabled', false);
	  $('#payment_amount').prop('disabled', false)
      $('#paypal-warning').hide();
    }
  }
}

$(document).ready(function() {
  checkedPaymentMethod = $('[data-hook="payment_method_field"] input[type="radio"]:checked');
  SpreePaypalExpress.hideSettings(checkedPaymentMethod);
  paymentMethods = $('[data-hook="payment_method_field"] input[type="radio"]').click(function (e) {
    SpreePaypalExpress.hideSettings($(e.target));
  });
})
