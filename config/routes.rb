# frozen_string_literal: true

require_dependency "discourse_post_event/engine"

DiscoursePostEvent::Engine.routes.draw do
  get "/events" => "events#index"
  get "/events/:id" => "events#show"
  delete "/events/:id" => "events#destroy"
  post "/events/:id/invite" => "events#invite"
  post "/events/:id/csv-bulk-invite" => "events#csv_bulk_invite"
  post "/events/:id/bulk-invite" => "events#bulk_invite"

  get "/events/:post_id/invitees" => "invitees#index"
  post "/events/:event_id/invitees" => "invitees#create"
  put "/events/:event_id/invitees/:invitee_id" => "invitees#update"
  delete "/events/:post_id/invitees/:id" => "invitees#destroy"

  get "/upcoming-events" => "upcoming_events#index"
  get "/upcoming-events/mine" => "upcoming_events#index"
end
