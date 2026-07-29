class AddStartedOnToStopwatchTimers < ActiveRecord::Migration[7.2]
  def change
    add_column :stopwatch_timers, :started_on, :date
  end
end
