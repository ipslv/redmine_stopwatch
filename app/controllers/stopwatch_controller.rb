# frozen_string_literal: true

class StopwatchController < ApplicationController
  before_action :require_login
  before_action :authorize_global
  before_action :find_timer,   only: %i[state start pause resume snap stop]
  before_action :find_segment, only: %i[save_segment delete_segment update_segment]

  # GET /stopwatch/state.json
  def state
    render json: timer_json
  end

  # POST /stopwatch/start.json
  def start
    resolve_context
    @timer.start!(issue_id: @context_issue_id, project_id: @context_project_id)
    render json: timer_json
  end

  # POST /stopwatch/pause.json
  def pause
    @timer.pause!
    render json: timer_json
  end

  # POST /stopwatch/resume.json
  def resume
    @timer.resume!
    render json: timer_json
  end

  # POST /stopwatch/snap.json
  def snap
    resolve_context
    @timer.snap!(new_issue_id: @context_issue_id, new_project_id: @context_project_id)
    render json: timer_json
  end

  # POST /stopwatch/stop.json
  def stop
    @timer.stop!
    render json: timer_json
  end

  # GET /stopwatch/segments
  def segments
    @timer = StopwatchTimer.find_or_initialize_by(user_id: User.current.id)
    @timer.state               ||= 'stopped'
    @timer.accumulated_seconds ||= 0

    @timer_activities         = TimeEntryActivity.available_activities(@timer.project)
    @timer_stored_activity_id = @timer.activity_id ||
                                TimeEntryActivity.default_activity_id(User.current, @timer.project)

    @segments_by_date = StopwatchSegment
      .where(user_id: User.current.id)
      .includes(:project, :issue)
      .order(spent_on: :desc, created_at: :desc)
      .group_by(&:spent_on)

    @allowed_projects   = Project.allowed_to(:log_time).to_a
    @default_project_id = Setting.plugin_redmine_stopwatch['default_project_id'].presence
    @default_project    = @default_project_id ? Project.find_by(id: @default_project_id) : nil

    spent_days = Setting.plugin_redmine_stopwatch['spent_time_days'].to_i
    spent_days = 2 if spent_days < 1
    today = User.current.today
    @spent_entries = TimeEntry
      .where(user_id: User.current.id)
      .where(spent_on: (today - (spent_days - 1))..today)
      .includes(:activity, :project, issue: [:tracker, :status])
      .order(spent_on: :desc, id: :desc)
      .to_a
    @spent_entries_by_day = @spent_entries.group_by(&:spent_on)
    @spent_total_hours    = @spent_entries.sum(&:hours)
    @spent_days           = spent_days

    @other_timers = []
    if User.current.allowed_to?(:view_stopwatch_others, nil, global: true)
      @other_timers = StopwatchTimer
        .where.not(user_id: User.current.id)
        .where(state: %w[running paused])
        .includes(:user, :project, issue: :tracker)
        .to_a
        .sort_by { |t| t.state == 'running' ? 0 : 1 }
    end
  end

  # POST /stopwatch/timer/update_comment
  def update_timer_comment
    timer = StopwatchTimer.find_by(user_id: User.current.id)
    if timer.nil? || timer.state == 'stopped'
      redirect_to stopwatch_segments_path and return
    end

    # Always save comments + activity first (copied to segment if snap happens)
    timer.update!(
      comments:    params[:comments].to_s.strip,
      activity_id: params[:activity_id].presence
    )

    # If user edited hours → validate and snap
    if params[:hours].present?
      new_seconds = parse_hours_to_seconds(params[:hours])
      unless new_seconds
        flash[:error] = l(:error_stopwatch_invalid_hours)
        redirect_to stopwatch_segments_path and return
      end

      if new_seconds < 60
        flash[:error] = l(:error_stopwatch_hours_too_small)
        redirect_to stopwatch_segments_path and return
      end

      elapsed = timer.elapsed_seconds
      if new_seconds > elapsed &&
         new_seconds - elapsed > max_hours_increase_seconds
        flash[:error] = l(:error_stopwatch_hours_increase_exceeded,
                           max: max_hours_increase_seconds / 60)
        redirect_to stopwatch_segments_path and return
      end

      timer.snap_with_hours!(new_seconds)
    end

    if params[:stop].present?
      timer.stop!
      flash[:notice] = l(:notice_successful_create)
      redirect_to stopwatch_segments_path and return
    end

    flash[:notice] = l(:notice_successful_update)
    redirect_to stopwatch_segments_path
  end

  # POST /stopwatch/segments/:id/update
  def update_segment
    if params[:comments].to_s.strip.blank?
      flash[:error] = l(:error_stopwatch_comments_required)
      redirect_to stopwatch_segments_path and return
    end

    new_seconds = validate_hours_param!(@segment.seconds)
    redirect_to(stopwatch_segments_path) and return unless new_seconds

    StopwatchSegment.transaction do
      # Split: create remainder with current (pre-update) stored values
      if new_seconds < @segment.seconds
        StopwatchSegment.create!(
          user_id:     @segment.user_id,
          project_id:  @segment.project_id,
          issue_id:    @segment.issue_id,
          seconds:     @segment.seconds - new_seconds,
          spent_on:    @segment.spent_on,
          activity_id: @segment.activity_id,
          comments:    @segment.comments
        )
      end

      @segment.update_fields!(
        project_id:  params[:project_id].presence,
        issue_id:    params[:issue_id].presence,
        activity_id: params[:activity_id].presence,
        comments:    params[:comments].to_s.strip,
        seconds:     new_seconds
      )
    end
    flash[:notice] = l(:notice_successful_update)
    redirect_to stopwatch_segments_path
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = e.message
    redirect_to stopwatch_segments_path
  end

  # POST /stopwatch/segments/:id/save
  def save_segment
    original_project_id  = @segment.project_id
    original_issue_id    = @segment.issue_id
    original_activity_id = @segment.activity_id
    original_comments    = @segment.comments
    original_seconds     = @segment.seconds

    @segment.project_id = params[:project_id].presence || original_project_id
    @segment.issue_id   = params[:issue_id].presence   || original_issue_id
    activity_id = params[:activity_id].presence || original_activity_id
    comments    = params[:comments]&.strip || original_comments.to_s

    new_seconds = validate_hours_param!(original_seconds)
    redirect_to(stopwatch_segments_path) and return unless new_seconds

    if @segment.project_id.blank?
      flash[:error] = l(:error_stopwatch_project_required)
      redirect_to stopwatch_segments_path and return
    end

    if activity_id.blank?
      flash[:error] = l(:error_stopwatch_activity_required)
      redirect_to stopwatch_segments_path and return
    end

    if comments.blank?
      flash[:error] = l(:error_stopwatch_comments_required)
      redirect_to stopwatch_segments_path and return
    end

    StopwatchSegment.transaction do
      # Remainder keeps original values; only the logged portion gets submitted values
      if new_seconds < original_seconds
        StopwatchSegment.create!(
          user_id:     @segment.user_id,
          project_id:  original_project_id,
          issue_id:    original_issue_id,
          seconds:     original_seconds - new_seconds,
          spent_on:    @segment.spent_on,
          activity_id: original_activity_id,
          comments:    original_comments
        )
      end

      # Update seconds in memory only — save_as_time_entry! reads self.seconds to compute hours,
      # then calls destroy!, so persisting to DB beforehand is not needed.
      @segment.seconds = new_seconds
      @segment.save_as_time_entry!(activity_id: activity_id, comments: comments)
    end
    flash[:notice] = l(:notice_successful_create)
    redirect_to stopwatch_segments_path
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = e.message
    redirect_to stopwatch_segments_path
  end

  # DELETE /stopwatch/segments/:id
  def delete_segment
    @segment.destroy!
    flash[:notice] = l(:notice_successful_delete)
    respond_to do |format|
      format.html { redirect_to stopwatch_segments_path }
      format.json { render json: { success: true } }
    end
  end

  # GET /stopwatch/issue_project/:issue_id.json
  # Returns the project_id for the given issue — used by segments page JS
  # to auto-fill the project dropdown without requiring the Redmine REST API.
  def issue_project
    issue = Issue.find_by(id: params[:issue_id])
    render json: { project_id: issue&.project_id }
  end

  private

  def find_timer
    @timer = StopwatchTimer.find_or_initialize_by(user_id: User.current.id)
    @timer.state               ||= 'stopped'
    @timer.accumulated_seconds ||= 0
  end

  def find_segment
    @segment = StopwatchSegment.find_by(id: params[:id], user_id: User.current.id)
    render_404 unless @segment
  end

  def resolve_context
    @context_issue_id   = nil
    @context_project_id = nil

    if params[:issue_id].present?
      issue = Issue.find_by(id: params[:issue_id])
      if issue
        @context_issue_id   = issue.id
        @context_project_id = issue.project_id
      end
    elsif params[:project_id].present?
      project = Project.find_by(identifier: params[:project_id]) ||
                Project.find_by(id: params[:project_id])
      @context_project_id = project&.id
    end
  end

  # Parses "H:MM" string → seconds (multiple of 60), or nil if invalid/zero
  def parse_hours_to_seconds(str)
    return nil if str.blank?
    match = str.strip.match(/\A(\d+):(\d{2})\z/)
    return nil unless match
    h = match[1].to_i
    m = match[2].to_i
    return nil if m >= 60
    return nil if h.zero? && m.zero?
    h * 3600 + m * 60
  end

  # Validates :hours param against original_seconds.
  # Returns resolved new_seconds on success, or nil (with flash[:error] set) on failure.
  def validate_hours_param!(original_seconds)
    new_seconds = parse_hours_to_seconds(params[:hours])
    unless new_seconds
      flash[:error] = l(:error_stopwatch_invalid_hours)
      return nil
    end

    # If user submitted the same ceil-rounded value they saw, keep original seconds
    displayed_seconds = ((original_seconds / 60.0).ceil) * 60
    new_seconds = original_seconds if new_seconds == displayed_seconds

    if new_seconds < 60
      flash[:error] = l(:error_stopwatch_hours_too_small)
      return nil
    end

    if new_seconds > original_seconds &&
       new_seconds - original_seconds > max_hours_increase_seconds
      flash[:error] = l(:error_stopwatch_hours_increase_exceeded,
                         max: max_hours_increase_seconds / 60)
      return nil
    end

    new_seconds
  end

  def max_hours_increase_seconds
    val = Setting.plugin_redmine_stopwatch['max_hours_increase']
    minutes = val.present? ? val.to_i : 60
    minutes.clamp(1, 480) * 60
  end

  def timer_json
    {
      state:                  @timer.state,
      elapsed_seconds:        @timer.elapsed_seconds,
      elapsed_display:        @timer.elapsed_display,
      started_at:             @timer.started_at&.utc&.iso8601,
      accumulated_seconds:    @timer.accumulated_seconds,
      pending_segments_count: StopwatchSegment.where(user_id: User.current.id).count
    }
  end
end
