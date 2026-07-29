class AddFieldsToStopwatchSegments < ActiveRecord::Migration[7.2]
  def change
    add_column :stopwatch_segments, :activity_id, :integer
    add_column :stopwatch_segments, :comments, :text
  end
end
