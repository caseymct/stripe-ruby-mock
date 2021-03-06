module StripeMock
  module RequestHandlers
    module Invoices

      def Invoices.included(klass)
        klass.add_handler 'post /v1/invoices',               :new_invoice
        klass.add_handler 'get /v1/invoices/upcoming',       :upcoming_invoice
        klass.add_handler 'get /v1/invoices/(.*)/lines',     :get_invoice_line_items
        klass.add_handler 'get /v1/invoices/(.*)',           :get_invoice
        klass.add_handler 'get /v1/invoices',                :list_invoices
        klass.add_handler 'post /v1/invoices/(.*)/pay',      :pay_invoice
        klass.add_handler 'post /v1/invoices/(.*)',          :update_invoice
      end

      def new_invoice(route, method_url, params, headers)
        id = new_id('in')
        new_invoice_items = []

        if subscription_id = params[:subscription]
          subscription = assert_existence :subscription, subscription_id, subscriptions[subscription_id]

          new_invoice_items = subscription[:items][:data].map do |d|
            plan = d[:plan]
            invoice_item = Data.mock_line_item({ amount: plan[:amount], plan: plan, subscription: subscription_id })
            invoice_items[invoice_item[:id]] = invoice_item
            invoice_item
          end
        else
          new_invoice_items = [Data.mock_line_item]
        end

        invoices[id] = Data.mock_invoice(new_invoice_items, params.merge(:id => id))
      end

      def update_invoice(route, method_url, params, headers)
        route =~ method_url
        params.delete(:lines) if params[:lines]
        assert_existence :invoice, $1, invoices[$1]
        invoices[$1].merge!(params)
      end

      def list_invoices(route, method_url, params, headers)
        params[:offset] ||= 0
        params[:limit] ||= 10

        result = invoices.clone

        if params[:customer]
          result.delete_if { |k,v| v[:customer] != params[:customer] }
        end

        Data.mock_list_object(result.values, params)
      end

      def get_invoice(route, method_url, params, headers)
        route =~ method_url
        assert_existence :invoice, $1, invoices[$1]
      end

      def get_invoice_line_items(route, method_url, params, headers)
        route =~ method_url
        assert_existence :invoice, $1, invoices[$1]
        invoices[$1][:lines]
      end

      def pay_invoice(route, method_url, params, headers)
        route =~ method_url
        assert_existence :invoice, $1, invoices[$1]
        charge = invoice_charge(invoices[$1])
        invoices[$1].merge!(:paid => true, :attempted => true, :charge => charge[:id])
      end

      def upcoming_invoice(route, method_url, params, headers)
        route =~ method_url
        raise Stripe::InvalidRequestError.new('Missing required param: customer', nil, http_status: 400) if params[:customer].nil?

        customer = customers[params[:customer]]
        assert_existence :customer, params[:customer], customer

        raise Stripe::InvalidRequestError.new("No upcoming invoices for customer: #{customer[:id]}", nil, http_status: 404) if customer[:subscriptions][:data].length == 0

        most_recent = customer[:subscriptions][:data].min_by { |sub| sub[:current_period_end] }
        invoice_item = get_mock_subscription_line_item(most_recent)

        id = new_id('in')
        invoices[id] = Data.mock_invoice([invoice_item],
          id: id,
          customer: customer[:id],
          subscription: most_recent[:id],
          period_start: most_recent[:current_period_start],
          period_end: most_recent[:current_period_end],
          next_payment_attempt: most_recent[:current_period_end] + 3600 )
      end

      private

      def get_mock_subscription_line_item(subscription)
        Data.mock_line_item(
          id: subscription[:id],
          type: "subscription",
          plan: subscription[:plan],
          amount: subscription[:plan][:amount],
          discountable: true,
          quantity: 1,
          period: {
            start: subscription[:current_period_end],
            end: get_ending_time(subscription[:current_period_start], subscription[:plan], 2)
          })
      end

      ## charge the customer on the invoice, if one does not exist, create
      #anonymous charge
      def invoice_charge(invoice)
        begin
          new_charge(nil, nil, {customer: invoice[:customer]["id"], amount: invoice[:amount_due], currency: 'usd'}, nil)
        rescue Stripe::InvalidRequestError
          new_charge(nil, nil, {source: generate_card_token, amount: invoice[:amount_due], currency: 'usd'}, nil)
        end
      end

    end
  end
end
