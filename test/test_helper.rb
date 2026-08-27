ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Deliberately serial. Three test files stub R2 by redefining a singleton method for
    # the duration of a block - process-wide state, which threads share, so in parallel one
    # test's stub leaks into another's and pg reports the shared connection as "message type
    # 0x49 arrived from server while idle". The whole suite runs in about five seconds; there
    # is nothing here for parallelism to buy. Rails only crosses this bridge above 50 tests,
    # which is why it worked until the suite grew past that.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
