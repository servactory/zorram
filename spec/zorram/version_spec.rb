# frozen_string_literal: true

RSpec.describe Zorram::VERSION do
  it { expect(Zorram::VERSION::STRING).to be_present }
end
