# frozen_string_literal: true

class Point < ApplicationRecord
  include Nearable
  include Distanceable

  belongs_to :import, optional: true, counter_cache: true
  belongs_to :visit, optional: true
  belongs_to :user

  validates :timestamp, :lonlat, presence: true
  validates :lonlat, uniqueness: {
    scope: %i[timestamp user_id],
    message: 'already has a point at this location and time for this user',
    index: true
  }

  enum :battery_status, { unknown: 0, unplugged: 1, charging: 2, full: 3 }, suffix: true
  enum :trigger, {
    unknown: 0, background_event: 1, circular_region_event: 2, beacon_event: 3,
    report_location_message_event: 4, manual_event: 5, timer_based_event: 6,
    settings_monitoring_event: 7
  }, suffix: true
  enum :connection, { mobile: 0, wifi: 1, offline: 2, unknown: 4 }, suffix: true

  scope :reverse_geocoded, -> { where.not(reverse_geocoded_at: nil) }
  scope :not_reverse_geocoded, -> { where(reverse_geocoded_at: nil) }
  scope :visited, -> { where.not(visit_id: nil) }
  scope :not_visited, -> { where(visit_id: nil) }

  after_create :async_reverse_geocode
  after_create_commit :broadcast_coordinates
  after_commit -> { Import::UpdatePointsCountJob.perform_later(import_id) }, on: :destroy, if: -> { import_id.present? }

  def self.without_raw_data
    select(column_names - ['raw_data'])
  end

  def recorded_at
    @recorded_at ||= Time.zone.at(timestamp)
  end

  def async_reverse_geocode
    return unless DawarichSettings.reverse_geocoding_enabled?

    ReverseGeocodingJob.perform_later(self.class.to_s, id)
  end

  def reverse_geocoded?
    reverse_geocoded_at.present?
  end

  def lon
    lonlat.x
  end

  def lat
    lonlat.y
  end

  private

  # rubocop:disable Metrics/MethodLength Metrics/AbcSize
  def broadcast_coordinates
    PointsChannel.broadcast_to(
      user,
      [
        lat,
        lon,
        battery.to_s,
        altitude.to_s,
        timestamp.to_s,
        velocity.to_s,
        id.to_s,
        country.to_s
      ]
    )
  end
  # rubocop:enable Metrics/MethodLength
end
