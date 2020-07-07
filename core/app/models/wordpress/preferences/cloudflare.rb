# Use singleton class Wordpress::Preferences::Cloudflare.instance to access
#
# StoreInstance has a persistence flag that is on by default,
# but we disable database persistence in testing to speed up tests
#

require 'singleton'

DB_EXCEPTIONS = if defined? PG
                  [PG::ConnectionBad, ActiveRecord::NoDatabaseError]
                elsif defined? Mysql2
                  [Mysql2::Error::ConnectionError, ActiveRecord::NoDatabaseError]
                else
                  [ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError]
                end

module Wordpress::Preferences
  class CloudflareInstance
    attr_accessor :persistence

    def initialize
      @cache = Rails.cache
      @persistence = true
    end

    def set(key, value)
      @cache.write(key, value)
      persist(key, value)
    end
    alias []= set

    def exist?(key)
      @cache.exist?(key) ||
        should_persist? && Wordpress::Preference.where(key: key).exists?
    end

    def get(key)
      # return the retrieved value, if it's in the cache
      # use unless nil? incase the value is actually boolean false
      #
      unless (val = @cache.read(key)).nil?
        return val
      end

      if should_persist?
        # If it's not in the cache, maybe it's in the database, but
        # has been cleared from the cache

        # does it exist in the database?
        val = if preference = Wordpress::Preference.find_by(key: key)
                # it does exist
                preference.value
              else
                # use the fallback value
                yield
              end

        # Cache either the value from the db or the fallback value.
        # This avoids hitting the db with subsequent queries.
        @cache.write(key, val)

        return val
      else
        yield
      end
    end
    alias fetch get

    def delete(key)
      @cache.delete(key)
      destroy(key)
    end

    def clear_cache
      @cache.clear
    end

    private

    def persist(cache_key, value)
      return unless should_persist?

      preference = Wordpress::Preference.where(key: cache_key).first_or_initialize
      preference.value = value
      preference.save
    end

    def destroy(cache_key)
      return unless should_persist?

      preference = Wordpress::Preference.find_by(key: cache_key)
      preference&.destroy
    end

    def should_persist?
      @persistence && Wordpress::Preference.table_exists?
    rescue *DB_EXCEPTIONS # this is fix to make Deploy To Heroku button work
      false
    end
  end

  class Cloudflare < CloudflareInstance
    include Singleton
  end
end