# frozen_string_literal: true

class CreateDiscoursePostEventTables < ActiveRecord::Migration[6.0]
  def change
    create_table :discourse_post_event_events do |t|
      t.integer :id, primary_key: true
      t.integer :status, default: 0, null: false
      t.datetime :original_starts_at, null: false
      t.datetime :original_ends_at
      t.datetime :deleted_at
      t.string :raw_invitees, array: true
      t.string :name
      t.string :url, limit: 1000
      t.string :description, limit: 1000
      t.string :location, limit: 1000
      t.jsonb :custom_fields, null: false, default: {}
      t.string :reminders
      t.string :recurrence
      t.string :timezone
      t.boolean :minimal
      t.boolean :closed, default: false, null: false
      t.boolean :chat_enabled, default: false, null: false
      t.bigint :chat_channel_id
      t.datetime :recurrence_until
      t.boolean :show_local_time, default: false, null: false
    end

    create_table :discourse_post_event_invitees do |t|
      t.integer :post_id, null: false
      t.integer :user_id, null: false
      t.integer :status
      t.boolean :notified, null: false, default: false
      t.timestamps null: false
    end
    add_index :discourse_post_event_invitees, [:post_id, :user_id], unique: true

    create_table :discourse_post_event_dates do |t|
      t.integer :event_id, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.integer :reminder_counter, default: 0
      t.datetime :event_will_start_sent_at
      t.datetime :event_started_sent_at
      t.datetime :finished_at
      t.timestamps null: false
    end
    add_index :discourse_post_event_dates, :event_id
    add_index :discourse_post_event_dates, :finished_at
  end
end
