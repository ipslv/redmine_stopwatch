class ConvertStopwatchColumnsToUtf8 < ActiveRecord::Migration[7.2]
  def up
    change_column :stopwatch_segments, :comments, :text,
                  charset: 'utf8', collation: 'utf8_general_ci'
    change_column :stopwatch_timers, :state, :string,
                  null: false, default: 'stopped',
                  charset: 'utf8', collation: 'utf8_general_ci'
  end

  def down
    change_column :stopwatch_segments, :comments, :text
    change_column :stopwatch_timers, :state, :string,
                  null: false, default: 'stopped'
  end
end
