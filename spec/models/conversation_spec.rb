# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversation, type: :model do
  describe '.before_create' do
    let(:conversation) { build(:complete_conversation, display_id: nil) }

    before do
      conversation.save
      conversation.reload
    end

    it 'runs before_create callbacks' do
      expect(conversation.display_id).to eq(1)
    end
  end

  describe '.after_update' do
    let(:account) { create(:account) }
    let(:conversation) do
      create(:complete_conversation, status: 'open', account: account, assignee: old_assignee)
    end
    let(:old_assignee) do
      create(:user, email: 'agent1@example.com', account: account, role: :agent)
    end
    let(:new_assignee) do
      create(:user, email: 'agent2@example.com', account: account, role: :agent)
    end
    let(:assignment_mailer) { double(deliver: true) }

    before do
      conversation
      new_assignee

      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      allow(AssignmentMailer).to receive(:conversation_assigned).and_return(assignment_mailer)
      allow(assignment_mailer).to receive(:deliver)
      Current.user = old_assignee

      conversation.update(
        status: :resolved,
        locked: true,
        user_last_seen_at: Time.now,
        assignee: new_assignee
      )
    end

    it 'runs after_update callbacks' do
      # notify_status_change
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(described_class::CONVERSATION_RESOLVED, kind_of(Time), conversation: conversation)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(described_class::CONVERSATION_READ, kind_of(Time), conversation: conversation)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(described_class::CONVERSATION_LOCK_TOGGLE, kind_of(Time), conversation: conversation)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(described_class::ASSIGNEE_CHANGED, kind_of(Time), conversation: conversation)

      # send_email_notification_to_assignee
      expect(AssignmentMailer).to have_received(:conversation_assigned).with(conversation, new_assignee)

      expect(assignment_mailer).to have_received(:deliver) if ENV.fetch('SMTP_ADDRESS', nil).present?
    end

    it 'creates conversation activities' do
      # create_activity
      expect(conversation.messages.pluck(:content)).to include("Conversation was marked resolved by #{old_assignee.name}")
      expect(conversation.messages.pluck(:content)).to include("Assigned to #{new_assignee.name} by #{old_assignee.name}")
    end
  end

  describe '.after_create' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, email: 'agent1@example.com', account: account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) do
      create(
        :conversation,
        account: account,
        contact: create(:contact, account: account),
        inbox: inbox,
        assignee: nil
      )
    end

    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      allow(Redis::Alfred).to receive(:rpoplpush).and_return(agent.id)
    end

    it 'runs after_create callbacks' do
      # send_events
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(described_class::CONVERSATION_CREATED, kind_of(Time), conversation: conversation)

      # run_round_robin
      expect(conversation.reload.assignee).to eq(agent)
    end
  end

  describe '#update_assignee' do
    subject(:update_assignee) { conversation.update_assignee(agent) }

    let(:conversation) { create(:complete_conversation, assignee: nil) }
    let(:agent) do
      create(:user, email: 'agent@example.com', account: conversation.account, role: :agent)
    end

    it 'assigns the agent to conversation' do
      expect(update_assignee).to eq(true)
      expect(conversation.reload.assignee).to eq(agent)
    end
  end

  describe '#toggle_status' do
    subject(:toggle_status) { conversation.toggle_status }

    let(:conversation) { create(:complete_conversation, status: :open) }

    it 'toggles conversation status' do
      expect(toggle_status).to eq(true)
      expect(conversation.reload.status).to eq('resolved')
    end
  end

  describe '#lock!' do
    subject(:lock!) { conversation.lock! }

    let(:conversation) { create(:complete_conversation) }

    it 'assigns locks the conversation' do
      expect(lock!).to eq(true)
      expect(conversation.reload.locked).to eq(true)
    end
  end

  describe '#unlock!' do
    subject(:unlock!) { conversation.unlock! }

    let(:conversation) { create(:complete_conversation) }

    it 'unlocks the conversation' do
      expect(unlock!).to eq(true)
      expect(conversation.reload.locked).to eq(false)
    end
  end

  describe 'unread_messages' do
    subject(:unread_messages) { conversation.unread_messages }

    let(:conversation) { create(:complete_conversation, agent_last_seen_at: 1.hour.ago) }
    let(:message_params) do
      {
        conversation: conversation,
        account: conversation.account,
        inbox: conversation.inbox,
        user: conversation.assignee
      }
    end
    let!(:message) do
      create(:message, created_at: 1.minute.ago, **message_params)
    end

    before do
      create(:message, created_at: 1.month.ago, **message_params)
    end

    it 'returns unread messages' do
      expect(unread_messages).to include(message)
    end
  end

  describe 'unread_incoming_messages' do
    subject(:unread_incoming_messages) { conversation.unread_incoming_messages }

    let(:conversation) { create(:complete_conversation, agent_last_seen_at: 1.hour.ago) }
    let(:message_params) do
      {
        conversation: conversation,
        account: conversation.account,
        inbox: conversation.inbox,
        user: conversation.assignee,
        created_at: 1.minute.ago
      }
    end
    let!(:message) do
      create(:message, message_type: :incoming, **message_params)
    end

    before do
      create(:message, message_type: :outgoing, **message_params)
    end

    it 'returns unread incoming messages' do
      expect(unread_incoming_messages).to contain_exactly(message)
    end
  end

  describe '#push_event_data' do
    subject(:push_event_data) { conversation.push_event_data }

    let(:conversation) { create(:complete_conversation) }
    let(:expected_data) do
      {
        meta: {
          sender: conversation.contact.push_event_data,
          assignee: conversation.assignee
        },
        id: conversation.display_id,
        messages: [],
        inbox_id: conversation.inbox_id,
        status: conversation.status_before_type_cast.to_i,
        timestamp: conversation.created_at.to_i,
        user_last_seen_at: conversation.user_last_seen_at.to_i,
        agent_last_seen_at: conversation.agent_last_seen_at.to_i,
        unread_count: 0
      }
    end

    it 'returns push event payload' do
      expect(push_event_data).to eq(expected_data)
    end
  end

  describe '#lock_event_data' do
    subject(:lock_event_data) { conversation.lock_event_data }

    let(:conversation) do
      build(:conversation, display_id: 505, locked: false)
    end

    it 'returns lock event payload' do
      expect(lock_event_data).to eq(id: 505, locked: false)
    end
  end
end
