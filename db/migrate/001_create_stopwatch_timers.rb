class CreateStopwatchTimers < ActiveRecord::Migration[7.2]
  def change
    create_table :stopwatch_timers do |t|
      t.integer  :user_id,             null: false
      t.string   :state,               null: false, default: 'stopped'
      t.datetime :started_at
      t.integer  :accumulated_seconds, null: false, default: 0
      t.integer  :issue_id
      t.integer  :project_id
      t.timestamps
    end

    add_index :stopwatch_timers, :user_id, unique: true
  end
end
