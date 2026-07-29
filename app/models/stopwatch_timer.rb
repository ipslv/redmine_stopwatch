# frozen_string_literal: true

class StopwatchTimer < ApplicationRecord
  belongs_to :user
  belongs_to :project,  optional: true
  belongs_to :issue,    optional: true
  belongs_to :activity, class_name: 'TimeEntryActivity', optional: true

  STATES = %w[stopped running paused].freeze

  validates :state, inclusion: { in: STATES }

  # Total elapsed seconds, including live time if currently running
  def elapsed_seconds
    base = accumulated_seconds || 0
    if state == 'running' && started_at.present?
      base + (Time.now.utc - started_at).to_i
    else
      base
    end
  end

  # Elapsed time formatted as "H:MM"
  def elapsed_display
    secs = elapsed_seconds
    total_minutes = secs / 60
    hours   = total_minutes / 60
    minutes = total_minutes % 60
    "#{hours}:#{format('%02d', minutes)}"
  end

  # Elapsed time as fractional hours (for TimeEntry.hours)
  def elapsed_hours
    elapsed_seconds / 3600.0
  end

  # --- State transitions ---

  def start!(issue_id: nil, project_id: nil)
    self.state               = 'running'
    self.started_at          = Time.now.utc
    self.started_on          = Time.now.utc.to_date
    self.accumulated_seconds = 0
    self.issue_id            = issue_id
    self.project_id          = project_id
    self.comments            = nil
    self.activity_id         = nil
    save!
  end

  def pause!
    return unless state == 'running'

    self.accumulated_seconds = elapsed_seconds
    self.started_at          = nil
    self.state               = 'paused'
    save!
  end

  def resume!
    return unless state == 'paused'

    self.started_at = Time.now.utc
    self.state      = 'running'
    save!
  end

  # Saves current segment, stops timer, returns the created segment (or nil)
  def stop!
    segment = build_and_save_segment
    reset!
    segment
  end

  # Saves current segment, resets counter to 0, continues running with new context
  # Note: if called while paused, also resumes the timer (design decision).
  def snap!(new_issue_id: nil, new_project_id: nil)
    segment = build_and_save_segment
    self.accumulated_seconds = 0
    self.started_at          = Time.now.utc
    self.started_on          = Time.now.utc.to_date
    self.state               = 'running'
    self.issue_id            = new_issue_id
    self.project_id          = new_project_id
    self.comments            = nil
    self.activity_id         = nil
    save!
    segment
  end

  # Saves a segment with custom seconds, adjusts timer accordingly.
  # Decrease (entered < elapsed): timer continues with remainder, keeps current state.
  # Increase/equal (entered >= elapsed): timer resets to 0 and continues running.
  # Note: comments/activity_id are intentionally NOT cleared — unlike snap!(), this method
  # is called from the Segments page to adjust hours within the same task context.
  def snap_with_hours!(entered_seconds)
    current = elapsed_seconds
    build_and_save_segment(entered_seconds)

    remainder = [current - entered_seconds, 0].max

    if remainder > 0
      self.accumulated_seconds = remainder
      self.started_at          = (state == 'running' ? Time.now.utc : nil)
    else
      self.accumulated_seconds = 0
      self.started_at          = Time.now.utc
      self.state               = 'running'
    end

    save!
  end

  private

  def build_and_save_segment(seconds_override = nil)
    secs = seconds_override || elapsed_seconds
    return nil if secs < 1

    StopwatchSegment.create!(
      user_id:     user_id,
      project_id:  project_id,
      issue_id:    issue_id,
      activity_id: activity_id,
      seconds:     secs,
      spent_on:    started_on || Time.now.utc.to_date,
      comments:    comments.presence
    )
  end

  def reset!
    self.state               = 'stopped'
    self.started_at          = nil
    self.started_on          = nil
    self.accumulated_seconds = 0
    self.issue_id            = nil
    self.project_id          = nil
    self.comments            = nil
    self.activity_id         = nil
    save!
  end
end
