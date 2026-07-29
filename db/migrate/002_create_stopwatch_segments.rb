class CreateStopwatchSegments < ActiveRecord::Migration[7.2]
  def change
    create_table :stopwatch_segments do |t|
      t.integer :user_id,    null: false
      t.integer :project_id
      t.integer :issue_id
      t.integer :seconds,    null: false
      t.date    :spent_on,   null: false
      t.timestamps
    end

    add_index :stopwatch_segments, :user_id
  end
end
