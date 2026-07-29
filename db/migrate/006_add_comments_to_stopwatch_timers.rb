class AddCommentsToStopwatchTimers < ActiveRecord::Migration[7.2]
  def change
    add_column :stopwatch_timers, :comments, :text,
               charset: 'utf8', collation: 'utf8_general_ci'
  end
end
