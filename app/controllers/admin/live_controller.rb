module Admin
  # Which shops are still talking to us. Everything here is a view over last_check_at - the
  # agent writes it on every licence check - so there is no new endpoint, no heartbeat table
  # and nothing for a shop to do differently.
  class LiveController < BaseController
    # Broken first: this page exists to be scanned for trouble, and a hundred healthy shops
    # must not push the one silent shop off the bottom.
    ORDER = { "down" => 0, "never" => 1, "late" => 2, "live" => 3 }.freeze

    def index
      now = Time.current
      shops = Shop.includes(:license).to_a

      @states = shops.index_with { |shop| shop.license&.agent_state(now) || "never" }
      @counts = @states.values.tally
      @shops  = shops.sort_by do |shop|
        # Oldest silence first inside a group; a shop that has never checked in has no
        # timestamp to sort by and goes to the top of its own.
        [ ORDER.fetch(@states[shop], 9), shop.license&.last_check_at || Time.at(0) ]
      end
    end
  end
end
