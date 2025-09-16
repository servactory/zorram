# frozen_string_literal: true

class Task < Zorram::Model
  include AASM

  expires_in 2.seconds

  attribute :id, :integer

  attribute :name, :string

  attribute :description, :string

  attribute :status, :string
  attribute :inspection, :string

  kredis_hash :attributes, key: ->(record) { "collection::attempt:#{record.id}" }

  aasm(:status, column: :status) do
    state :created, initial: true
    state :processed
    state :failed

    event :process do
      transitions from: :created, to: :processed
    end
    event :fail do
      transitions from: :created, to: :failed
    end
  end

  aasm(:inspection, column: :inspection, namespace: :inspection) do
    state :enqueued, initial: true
    state :passed
    state :failed

    event :pass do
      transitions from: :enqueued, to: :passed
    end
    event :fail do
      transitions from: :enqueued, to: :failed
    end
  end
end
