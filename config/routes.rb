RedmineApp::Application.routes.draw do
  # Timer control (JSON API)
  get  'stopwatch/state',  to: 'stopwatch#state',  as: 'stopwatch_state',  defaults: { format: :json }
  post 'stopwatch/start',  to: 'stopwatch#start',  as: 'stopwatch_start',  defaults: { format: :json }
  post 'stopwatch/pause',  to: 'stopwatch#pause',  as: 'stopwatch_pause',  defaults: { format: :json }
  post 'stopwatch/resume', to: 'stopwatch#resume', as: 'stopwatch_resume', defaults: { format: :json }
  post 'stopwatch/snap',   to: 'stopwatch#snap',   as: 'stopwatch_snap',   defaults: { format: :json }
  post 'stopwatch/stop',   to: 'stopwatch#stop',   as: 'stopwatch_stop',   defaults: { format: :json }

  # Segments page (HTML)
  get    'stopwatch/segments',              to: 'stopwatch#segments',       as: 'stopwatch_segments'
  post   'stopwatch/segments/:id/update',   to: 'stopwatch#update_segment', as: 'stopwatch_update_segment'
  post   'stopwatch/segments/:id/save',     to: 'stopwatch#save_segment',   as: 'stopwatch_save_segment'
  delete 'stopwatch/segments/:id',          to: 'stopwatch#delete_segment', as: 'stopwatch_delete_segment'

  # Timer comment save
  post 'stopwatch/timer/update_comment', to: 'stopwatch#update_timer_comment',
                                          as: 'stopwatch_update_timer_comment'

  # Issue project lookup (replaces direct /issues/:id.json REST API call)
  get    'stopwatch/issue_project/:issue_id', to: 'stopwatch#issue_project', as: 'stopwatch_issue_project',
                                              defaults: { format: :json }
end
