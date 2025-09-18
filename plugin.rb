# name: discourse-events
# about: A standalone plugin to create events in Discourse posts.
# version: 1.0
# authors: Your Name
# url: https://github.com/your-repo/discourse-events

enabled_site_setting :discourse_post_event_enabled

# --- CSS Assets ---
register_asset "stylesheets/common/discourse-post-event.scss"
register_asset "stylesheets/common/post-event-builder.scss"
register_asset "stylesheets/common/discourse-post-event-bulk-invite-modal.scss"
register_asset "stylesheets/common/discourse-post-event-core-ext.scss"
register_asset "stylesheets/common/discourse-post-event-invitees.scss"
register_asset "stylesheets/common/discourse-post-event-preview.scss"
register_asset "stylesheets/common/discourse-post-event-upcoming-events.scss"
register_asset "stylesheets/common/upcoming-events-calendar.scss"
register_asset "stylesheets/common/upcoming-events-list.scss"
register_asset "stylesheets/desktop/discourse-post-event-invitees.scss", :desktop
register_asset "stylesheets/mobile/discourse-post-event.scss", :mobile
register_asset "stylesheets/mobile/discourse-post-event-core-ext.scss", :mobile
register_asset "stylesheets/mobile/discourse-post-event-invitees.scss", :mobile

# --- SVG Icons ---
register_svg_icon "calendar-day"
register_svg_icon "clock"
register_svg_icon "file-csv"
register_svg_icon "star"
register_svg_icon "file-arrow-up"
register_svg_icon "location-pin"

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
  require_relative "app/serializers/discourse_post_event/event_stats_serializer"
  require_relative "app/serializers/discourse_post_event/invitee_list_serializer"
  require_relative "lib/discourse_post_event/event_parser"
  require_relative "lib/discourse_post_event/event_validator"
  require_relative "lib/discourse_post_event/post_extension"
  require_relative "lib/discourse_post_event/event_finder"
  require_relative "lib/discourse_post_event/rrule_generator"
  require_relative "lib/discourse_post_event/rrule_configurator"
  require_relative "jobs/regular/discourse_post_event/bulk_invite"
  require_relative "jobs/regular/discourse_post_event/send_reminder"
  require_relative "jobs/scheduled/monitor_event_dates"

  # Mount the plugin's engine
  Discourse::Application.routes.append do
    mount ::DiscoursePostEvent::Engine, at: "/discourse-post-event"
  end

  # Add a custom validator to the Post model
  Post.prepend DiscoursePostEvent::PostExtension

  # Listen for post events
  on(:post_created) { |post| DiscoursePostEvent::Event.update_from_raw(post) }
  on(:post_edited) { |post| DiscoursePostEvent::Event.update_from_raw(post) }
  on(:post_destroyed) { |post| post.event.update!(deleted_at: Time.now) if post.event }
  on(:post_recovered) { |post| post.event.update!(deleted_at: nil) if post.event }
  on(:user_destroyed) { |user| DiscoursePostEvent::Invitee.where(user_id: user.id).destroy_all }

  # Add event data to the PostSerializer
  add_to_serializer(:post, :event, include_condition: -> { SiteSetting.discourse_post_event_enabled && object.event.present? && !object.event.deleted_at.present? }) do
    DiscoursePostEvent::EventSerializer.new(object.event, scope: scope, root: false)
  end

  # Preload event data with posts
  TopicView.on_preload do |topic_view|
    if SiteSetting.discourse_post_event_enabled
      topic_view.instance_variable_set(:@posts, topic_view.posts.includes(:event))
    end
  end

  # Add custom fields for topic list display
  add_preloaded_topic_list_custom_field DiscoursePostEvent::TOPIC_POST_EVENT_STARTS_AT
  add_to_serializer(:topic_list_item, :event_starts_at, include_condition: -> { object.event_starts_at.present? }) { object.event_starts_at }
  add_to_class(:topic, :event_starts_at) { custom_fields[DiscoursePostEvent::TOPIC_POST_EVENT_STARTS_AT] }

  add_preloaded_topic_list_custom_field DiscoursePostEvent::TOPIC_POST_EVENT_ENDS_AT
  add_to_serializer(:topic_list_item, :event_ends_at, include_condition: -> { object.event_ends_at.present? }) { object.event_ends_at }
  add_to_class(:topic, :event_ends_at) { custom_fields[DiscoursePostEvent::TOPIC_POST_EVENT_ENDS_AT] }

  # Permissions
  add_to_class(:user, :can_create_discourse_post_event?) do
    return @can_create_discourse_post_event if defined?(@can_create_discourse_post_event)
    @can_create_discourse_post_event =
      begin
        return true if staff?
        allowed_groups = SiteSetting.discourse_post_event_allowed_on_groups.to_s.split("|").compact
        allowed_groups.present? && (allowed_groups.include?(Group::AUTO_GROUPS[:everyone].to_s) || groups.where(id: allowed_groups).exists?)
      rescue StandardError
        false
      end
  end

  add_to_class(:guardian, :can_create_discourse_post_event?) do
    user && user.can_create_discourse_post_event?
  end

  add_to_serializer(:current_user, :can_create_discourse_post_event) do
    object.can_create_discourse_post_event?
  end

  add_to_class(:user, :can_act_on_discourse_post_event?) do |event|
    return true if staff?
    can_create_discourse_post_event? && Guardian.new(self).can_edit_post?(event.post)
  end

  add_to_class(:guardian, :can_act_on_discourse_post_event?) do |event|
    user && user.can_act_on_discourse_post_event?(event)
  end

  add_to_class(:guardian, :can_act_on_invitee?) do |invitee|
    user && (user.staff? || user.id == invitee.user_id)
  end
end
