# frozen_string_literal: true

class AddActivityIdToStopwatchTimers < ActiveRecord::Migration[7.2]
  def change
    add_column :stopwatch_timers, :activity_id, :integer, null: true
  end
end
