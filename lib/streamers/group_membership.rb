# frozen_string_literal: true

module ::Streamers
  # Responsible for (optionally) managing membership of the configured Streamers group.
  #
  # Design goal: be conservative to avoid breaking existing setups.
  # - When auto-manage is enabled, we **add** eligible users (trust level >= min) to the group.
  # - We always enforce the force-exclude list (remove from group if excluded).
  # - We do NOT automatically remove users just because they are below the min trust level,
  #   so manual overrides (adding a user to the group) keep working.
  module GroupMembership
    module_function

    # Discourse events are not perfectly consistent across versions/plugins.
    # Some callbacks pass a User instance, others pass an id. We accept both.
    def resolve_user(user_or_id)
      return user_or_id if user_or_id.is_a?(::User)

      id =
        if user_or_id.is_a?(Integer)
          user_or_id
        else
          str = user_or_id.to_s
          str.match?(/\A\d+\z/) ? str.to_i : nil
        end

      return nil if id.blank?
      ::User.find_by(id: id)
    end

    def normalized_group_name
      SiteSetting.streamers_group_name.to_s.strip.downcase
    end

    def streamers_group
      name = normalized_group_name
      return nil if name.blank?
      # Be tolerant of case differences.
      Group.where("LOWER(name) = ?", name).first
    end

    def streamers_group_match?(group)
      return false if group.blank?
      group.name.to_s.downcase == normalized_group_name
    end

    def excluded_usernames
      raw = SiteSetting.streamers_force_exclude_from_streamers
      list = raw.is_a?(Array) ? raw : raw.to_s.split("|")
      list.map { |u| u.to_s.strip.downcase }.reject(&:blank?)
    end

    def auto_manage?
      SiteSetting.streamers_enabled? && SiteSetting.streamers_auto_manage_group?
    end

    def min_trust_level
      SiteSetting.streamers_min_trust_level.to_i
    end

    def user_excluded?(user)
      return false if user.blank?
      excluded_usernames.include?(user.username.to_s.downcase)
    end

    def eligible_for_auto_membership?(user)
      return false if user.blank?
      user.trust_level.to_i >= min_trust_level && !user_excluded?(user)
    end

    # Ensure membership for a single user.
    #
    # If the user is excluded, we remove them from the group (if present).
    # If eligible, we add them to the group (if missing).
    # Otherwise, do nothing.
    def ensure_membership!(user)
      return unless auto_manage?

      group = streamers_group
      return if group.blank?

      if user_excluded?(user)
        remove_from_group(group, user)
        return
      end

      if eligible_for_auto_membership?(user)
        add_to_group(group, user)
      end
    end

    # Wrapper used by event hooks to guarantee we never break core flows
    # (e.g. changing trust level in admin).
    def ensure_membership_safely(user_or_id)
      user = resolve_user(user_or_id)
      return if user.blank?

      ensure_membership!(user)
    rescue StandardError => e
      Rails.logger.warn("[streamers] ensure_membership_safely failed for #{user_or_id.inspect}: #{e.class} #{e.message}")
    end

    # Periodic sync to catch existing users and setting changes.
    def sync_all!
      return unless auto_manage?

      group = streamers_group
      return if group.blank?

      excluded = excluded_usernames

      # 1) Enforce exclusions (always remove excluded users from the group)
      if excluded.present?
        group.users.where("LOWER(users.username) IN (?)", excluded).find_each do |u|
          remove_from_group(group, u)
        end
      end

      # 2) Add all eligible users (trust >= min, not excluded)
      scope = User.where("trust_level >= ?", min_trust_level)
      if excluded.present?
        scope = scope.where.not("LOWER(username) IN (?)", excluded)
      end

      scope.find_each do |u|
        add_to_group(group, u)
      end
    end

    def settings_affect_group_membership?(setting_name)
      %w[
        streamers_auto_manage_group
        streamers_min_trust_level
        streamers_group_name
        streamers_force_exclude_from_streamers
      ].include?(setting_name.to_s)
    end

    def add_to_group(group, user)
      return if group.blank? || user.blank?
      return if group.users.exists?(id: user.id)

      group.add(user)
    rescue StandardError => e
      Rails.logger.warn("[streamers] Could not add user #{user.id} to group #{group.name}: #{e.class} #{e.message}")
    end

    def remove_from_group(group, user)
      return if group.blank? || user.blank?
      return unless group.users.exists?(id: user.id)

      group.remove(user)
    rescue StandardError => e
      Rails.logger.warn("[streamers] Could not remove user #{user.id} from group #{group.name}: #{e.class} #{e.message}")
    end
  end
end
