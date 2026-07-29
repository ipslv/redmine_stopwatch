# frozen_string_literal: true

class StopwatchSegment < ApplicationRecord
  belongs_to :user
  belongs_to :project,  optional: true
  belongs_to :issue,    optional: true
  belongs_to :activity, class_name: 'TimeEntryActivity', optional: true,
                        foreign_key: :activity_id

  validates :seconds,  numericality: { greater_than: 0, only_integer: true }
  validates :spent_on, presence: true

  # Fractional hours for TimeEntry.hours
  def hours
    seconds / 3600.0
  end

  # Display format "H:MM" (rounds up to nearest minute)
  def time_display
    total_minutes = (seconds / 60.0).ceil
    h = total_minutes / 60
    m = total_minutes % 60
    "#{h}:#{format('%02d', m)}"
  end

  # Persists editable fields without creating a TimeEntry (Save action)
  def update_fields!(attrs)
    self.project_id  = attrs[:project_id]
    self.issue_id    = attrs[:issue_id]
    self.activity_id = attrs[:activity_id]
    self.comments    = attrs[:comments]
    self.seconds     = attrs[:seconds] if attrs.key?(:seconds)
    save!
  end

  # Creates a Redmine TimeEntry from this segment, then destroys self
  def save_as_time_entry!(activity_id: self.activity_id, comments: self.comments.to_s)
    te = TimeEntry.new(
      project_id:  project_id,
      issue_id:    issue_id,
      user:        user,
      author:      user,
      hours:       hours.round(2),
      activity_id: activity_id,
      comments:    comments,
      spent_on:    spent_on
    )
    TimeEntry.transaction do
      te.save!
      destroy!
    end
    te
  end
end
