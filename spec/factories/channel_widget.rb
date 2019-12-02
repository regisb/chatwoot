# frozen_string_literal: true

FactoryBot.define do
  factory :channel_widget, class: 'Channel::WebWidget' do
    sequence(:website_name) { |n| "Example Website #{n}" }
    sequence(:website_url) { |n| "https://example-#{n}.com" }
    account
    after(:create) do |channel_widget|
      create(:inbox, channel: channel_widget, account: channel_widget.account)
    end
  end
end
