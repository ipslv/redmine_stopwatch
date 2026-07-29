# frozen_string_literal: true

class StopwatchHookListener < Redmine::Hook::ViewListener
  # Inject plugin CSS and JS into <head>
  def view_layouts_base_html_head(context)
    return '' unless User.current.allowed_to?(:use_stopwatch, nil, global: true)

    context[:hook_caller].stylesheet_link_tag('stopwatch', plugin: 'redmine_stopwatch') +
      context[:hook_caller].javascript_include_tag('stopwatch', plugin: 'redmine_stopwatch')
  end

  # Inject timer widget div before #wrapper (JS will move it into #top-menu)
  def view_layouts_base_body_top(context)
    return '' unless User.current.allowed_to?(:use_stopwatch, nil, global: true)

    timer = StopwatchTimer.find_or_initialize_by(user_id: User.current.id)
    timer.state               ||= 'stopped'
    timer.accumulated_seconds ||= 0

    request       = context[:request]
    page_context  = detect_page_context(request.path)
    timer_context = detect_timer_context(timer)
    pending_count = StopwatchSegment.where(user_id: User.current.id).count

    context[:hook_caller].render(
      partial: 'stopwatch/widget',
      locals:  {
        timer:         timer,
        page_context:  page_context,
        timer_context: timer_context,
        pending_count: pending_count
      }
    )
  end

  private

  # Reserved Redmine path segments that are not project identifiers.
  # Single source of truth — serialised into data-reserved-paths on the widget and read by JS.
  RESERVED_PROJECT_PATH_SEGMENTS = %w[
    new edit copy autocomplete import archive unarchive close reopen
    settings modules members versions issues boards documents wiki
    activity repository search calendar gantt files news queries time_entries
  ].freeze
  RESERVED_PROJECT_PATHS = Regexp.new("\\A(#{RESERVED_PROJECT_PATH_SEGMENTS.join('|')})\\z")

  def detect_page_context(path)
    result = { label: nil, url: nil, issue_id: nil, project_id: nil }

    if (m = path.match(%r{/issues/(\d+)}))
      issue = Issue.find_by(id: m[1])
      if issue
        result[:label]      = "##{issue.id}"
        result[:url]        = "/issues/#{issue.id}"
        result[:issue_id]   = issue.id.to_s
        result[:project_id] = issue.project_id.to_s
      end
    elsif (m = path.match(%r{/projects/([^/]+)}))
      identifier = m[1]
      unless RESERVED_PROJECT_PATHS.match?(identifier)
        project = Project.find_by(identifier: identifier)
        if project
          result[:label]      = truncate_name(project.name)
          result[:url]        = "/projects/#{project.identifier}"
          result[:project_id] = project.id.to_s
        end
      end
    end

    result
  end

  def detect_timer_context(timer)
    result = { label: nil, url: nil, issue_id: nil, project_id: nil }

    if timer.issue_id.present?
      issue = Issue.find_by(id: timer.issue_id)
      if issue
        result[:label]      = "##{issue.id}"
        result[:url]        = "/issues/#{issue.id}"
        result[:issue_id]   = issue.id.to_s
        result[:project_id] = issue.project_id.to_s
      end
    elsif timer.project_id.present?
      project = Project.find_by(id: timer.project_id)
      if project
        result[:label]      = truncate_name(project.name)
        result[:url]        = "/projects/#{project.identifier}"
        result[:project_id] = project.id.to_s
      end
    end

    result
  end

  def truncate_name(name, max_len = 20)
    name.length > max_len ? "#{name[0...max_len]}..." : name
  end
end
