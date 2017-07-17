module StripeMock
  module RequestHandlers
    module SubscriptionItems

      def SubscriptionItems.included(klass)
        klass.add_handler 'get /v1/subscription_items/(.*)', :retrieve_subscription_item
        klass.add_handler 'post /v1/subscription_items', :create_subscription_item
        klass.add_handler 'post /v1/subscription_items/(.*)', :update_subscription_item
        klass.add_handler 'delete /v1/subscription_items/(.*)', :delete_subscription_item
      end

      def retrieve_subscription_item(route, method_url, params, headers)
        route =~ method_url

        subscription_item = assert_existence :subscription_item, $1, subscription_items[$1]
        subscription = get_subscription_from_subscription_item(subscription_item[:id])

        assert_existence :subscription, subscription[:id], subscription
        subscription_item
      end

      def create_subscription_item(route, method_url, params, headers)
        route =~ method_url

        s_id = params[:subscription]
        subscription = assert_existence :subscription, s_id, subscriptions[s_id]
        verify_active_status(subscription)

        item = add_new_subscription_item params
        subscription[:items][:data] << item

        item
      end

      def update_subscription_item(route, method_url, params, headers)
        route =~ method_url

        subscription_item = assert_existence :subscription_item, $1, subscription_items[$1]
        subscription = get_subscription_from_subscription_item(subscription_item[:id])
        verify_active_status(subscription)

        if plan_id = params[:plan]
          plan = assert_existence :plan, plan_id, plans[plan_id]
          subscription_item.merge!({ plan: plan })

          subscription[:items][:data].reject! { |si| si[:id] == subscription_item[:id] }
          subscription[:items][:data] << subscription_item
        end

        subscription_item
      end

      def delete_subscription_item(route, method_url, params, headers)
        route =~ method_url

        item = assert_existence :subscription_item, $1, subscription_items[$1]
        subscription = get_subscription_from_subscription_item(item[:id])

        subscription[:items][:data].reject! { |si| si[:id] == item[:id] }
        subscription_items.delete item[:id]

        { id: item[:id], deleted: true }
      end
    end
  end
end
