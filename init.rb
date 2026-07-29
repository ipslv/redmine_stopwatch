# frozen_string_literal: true

require_relative 'lib/stopwatch_hook_listener'

Redmine::Plugin.register :redmine_stopwatch do
  name        'Redmine Stopwatch plugin'
  description 'Interactive stopwatch timer for time tracking'
  url         'https://github.com/ipslv/redmine_stopwatch.git'
  author      'SIA IPS (Claude Code)'
  author_url  'https://www.ips.lv'
  version     '1.5.2'

  requires_redmine version_or_higher: '6.1.0'

  settings default: { 'default_project_id' => '', 'spent_time_days' => '2', 'max_hours_increase' => '60' },
           partial: 'settings/stopwatch_settings'

  permission :use_stopwatch, {
    stopwatch: [:state, :start, :pause, :resume, :snap, :stop,
                :segments, :save_segment, :delete_segment, :update_segment,
                :update_timer_comment, :issue_project]
  }, require: :loggedin

  permission :view_stopwatch_others, {}, require: :loggedin
end
