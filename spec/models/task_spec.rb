# frozen_string_literal: true

RSpec.describe Task do
  subject(:task) { described_class.create!(name:, description:, status:, inspection:) }

  let(:name) { "My name" }
  let(:description) { "My description" }
  let(:status) { "created" }
  let(:inspection) { "enqueued" }

  describe "basis" do
    it { expect(task.id).to be_present && be_an(Integer) }

    it :aggregate_failures do
      id = task.id

      described_class.find(id).tap do |task|
        expect(task.id).to eq(id)
        expect(task.name).to eq("My name")
        expect(task.description).to eq("My description")
      end
    end

    it { expect(task.name).to eq("My name") }
    it { expect(task.description).to eq("My description") }

    it { expect { task.update!(id: 999_999_999) }.not_to(change(task, :id)) }

    it { expect(task.update!(name: "New name")).to eq("New name") }

    it do
      expect { described_class.find(0) }.to(
        raise_error(
          Zorram::Exceptions::NotFoundError,
          "Cannot find Task#0"
        )
      )
    end

    it "raises StorageExpiredError when trying to update after TTL expiration" do
      task

      # Wait longer than the configured expires_in (2.seconds) to avoid timing flakiness
      sleep 2.1

      expect { task.update!(name: "New name") }.to(
        raise_error(
          Zorram::Exceptions::StorageExpiredError,
          "Cannot update Task##{task.id}: storage expired or not found"
        ).and(
          not_change { task.name }
        )
      )
    end
  end

  describe "several" do
    let(:task_1) { described_class.create!(name: "Task 1", description: "Task 1 description") }
    let(:task_2) { described_class.create!(name: "Task 2", description: "Task 2 description") }

    it { expect(task_1.id).not_to eq(task_2.id) }
    it { expect(task_1.name).to eq("Task 1") }
    it { expect(task_1.description).to eq("Task 1 description") }
    it { expect(task_2.name).to eq("Task 2") }
    it { expect(task_2.description).to eq("Task 2 description") }
  end

  describe "aasm" do
    it { expect(task.start!).to be(true) }
    it { expect(task.pass_inspection!).to be(true) }

    it do
      expect { task.process! }.to(
        raise_error(
          AASM::InvalidTransition,
          "Event 'process' cannot transition from 'created'."
        )
      )
    end
  end
end
