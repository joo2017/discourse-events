# name: discourse-events
# about: A plugin to create events in Discourse.
# version: 0.1
# authors: Your Name
# url: https://github.com/your-repo/discourse-events

enabled_site_setting :discourse_post_event_enabled

register_asset "stylesheets/common/discourse-post-event.scss"
register_asset "stylesheets/mobile/discourse-post-event.scss", :mobile

module ::DiscoursePostEvent
  PLUGIN_NAME = "discourse-post-event"
  TOPIC_POST_EVENT_STARTS_AT = "TopicEventStartsAt"
  TOPIC_POST_EVENT_ENDS_AT = "TopicEventEndsAt"

  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscoursePostEvent
  end
end

after_initialize do
  # --- Backend ---
  require_relative "app/controllers/discourse_post_event/events_controller"
  require_relative "app/controllers/discourse_post_event/invitees_controller"
  require_relative "app/controllers/discourse_post_event/upcoming_events_controller"
  require_relative "app/models/discourse_post_event/event"
  require_relative "app/models/discourse_post_event/event_date"
  require_relative "app/models/discourse_post_event/invitee"
  require_relative "app/serializers/discourse_post_event/event_serializer"
  require_relative "app/serializers/discourse_post_event/event_summary_serializer"
  require_relative "app/serializers/discourse_post_event/invitee_serializer"
  require_relative "lib/discourse_post_event/event_parser"
  require_relative "lib/discourse_post_event/event_validator"
  require_relative "lib/discourse_post_event/post_extension"

  # Mount the plugin's engine
  Discourse::Application.routes.append do
    mount ::DiscoursePostEvent::Engine, at: "/discourse-post-event"
  end

  # Add a custom validator to the Post model
  Post.prepend DiscoursePostEvent::PostExtension

  # Listen for post creation and edit events to update the event
  on(:post_created) { |post| DiscoursePostEvent::Event.update_from_raw(post) }
  on(:post_edited) { |post| DiscoursePostEvent::Event.update_from_raw(post) }

  # Handle event deletion when a post is destroyed or recovered
  on(:post_destroyed) do |post|
    if post.event
      post.event.update!(deleted_at: Time.now)
    end
  end

  on(:post_recovered) do |post|
    if post.event
      post.event.update!(deleted_at: nil)
    end
  end

  # Add event data to the PostSerializer
  add_to_serializer(:post, :event, include_condition: -> { SiteSetting.discourse_post_event_enabled && object.event.present? && !object.event.deleted_at.present? }) do
    DiscoursePostEvent::EventSerializer.new(object.event, scope: scope, root: false)
  end

  # Preload the event data with the topic's posts
  TopicView.on_preload do |topic_view|
    if SiteSetting.discourse_post_event_enabled
      topic_view.instance_variable_set(:@posts, topic_view.posts.includes(:event))
    end
  end

  # Add custom fields to the topic for event dates to display in topic lists
  add_preloaded_topic_list_custom_field DiscoursePostEvent::TOPIC_POST_EVENT_STARTS_AT
  add_to_serializer(:topic_list_item, :event_starts_at, include_condition: -> { object.event_starts_at.present? }) do
    object.event_starts_at
  end
  add_to_class(:topic, :event_starts_at) do
    custom_fields[DiscoursePostEvent::TOPIC_POST_EVENT_STARTS_AT]
  end
end
