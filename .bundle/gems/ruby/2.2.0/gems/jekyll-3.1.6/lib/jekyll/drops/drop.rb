# encoding: UTF-8

module Jekyll
  module Drops
    class Drop < Liquid::Drop
      include Enumerable

      NON_CONTENT_METHODS = [:fallback_data, :collapse_document].freeze

      # Get or set whether the drop class is mutable.
      # Mutability determines whether or not pre-defined fields may be
      # overwritten.
      #
      # is_mutable - Boolean set mutability of the class (default: nil)
      #
      # Returns the mutability of the class
      def self.mutable(is_mutable = nil)
        if is_mutable
          @is_mutable = is_mutable
        else
          @is_mutable = false
        end
      end

      def self.mutable?
        @is_mutable
      end

      # Create a new Drop
      #
      # obj - the Jekyll Site, Collection, or Document required by the
      # drop.
      #
      # Returns nothing
      def initialize(obj)
        @obj = obj
        @mutations = {} # only if mutable: true
      end

      # Access a method in the Drop or a field in the underlying hash data.
      # If mutable, checks the mutations first. Then checks the methods,
      # and finally check the underlying hash (e.g. document front matter)
      # if all the previous places didn't match.
      #
      # key - the string key whose value to fetch
      #
      # Returns the value for the given key, or nil if none exists
      def [](key)
        if self.class.mutable? && @mutations.key?(key)
          @mutations[key]
        elsif self.class.invokable? key
          public_send key
        else
          fallback_data[key]
        end
      end

      # Set a field in the Drop. If mutable, sets in the mutations and
      # returns. If not mutable, checks first if it's trying to override a
      # Drop method and raises a DropMutationException if so. If not
      # mutable and the key is not a method on the Drop, then it sets the
      # key to the value in the underlying hash (e.g. document front
      # matter)
      #
      # key - the String key whose value to set
      # val - the Object to set the key's value to
      #
      # Returns the value the key was set to unless the Drop is not mutable
      # and the key matches a method in which case it raises a
      # DropMutationException.
      def []=(key, val)
        if respond_to?("#{key}=")
          public_send("#{key}=", val)
        elsif respond_to? key
          if self.class.mutable?
            @mutations[key] = val
          else
            raise Errors::DropMutationException, "Key #{key} cannot be set in the drop."
          end
        else
          fallback_data[key] = val
        end
      end

      # Generates a list of strings which correspond to content getter
      # methods.
      #
      # Returns an Array of strings which represent method-specific keys.
      def content_methods
        @content_methods ||= (
          self.class.instance_methods - Jekyll::Drops::Drop.instance_methods - NON_CONTENT_METHODS
        ).map(&:to_s).reject do |method|
          method.end_with?("=")
        end
      end

      # Check if key exists in Drop
      #
      # key - the string key whose value to fetch
      #
      # Returns true if the given key is present
      def key?(key)
        if self.class.mutable && @mutations.key?(key)
          true
        else
          respond_to?(key) || fallback_data.key?(key)
        end
      end

      # Generates a list of keys with user content as their values.
      # This gathers up the Drop methods and keys of the mutations and
      # underlying data hashes and performs a set union to ensure a list
      # of unique keys for the Drop.
      #
      # Returns an Array of unique keys for content for the Drop.
      def keys
        (content_methods |
          @mutations.keys |
          fallback_data.keys).flatten
      end

      # Generate a Hash representation of the Drop by resolving each key's
      # value. It includes Drop methods, mutations, and the underlying object's
      # data. See the documentation for Drop#keys for more.
      #
      # Returns a Hash with all the keys and values resolved.
      def to_h
        keys.each_with_object({}) do |(key, _), result|
          result[key] = self[key]
        end
      end
      alias_method :to_hash, :to_h

      # Inspect the drop's keys and values through a JSON representation
      # of its keys and values.
      #
      # Returns a pretty generation of the hash representation of the Drop.
      def inspect
        require 'json'
        JSON.pretty_generate to_h
      end

      # Generate a Hash for use in generating JSON.
      # This is useful if fields need to be cleared before the JSON can generate.
      #
      # Returns a Hash ready for JSON generation.
      def hash_for_json(state = nil)
        to_h
      end

      # Generate a JSON representation of the Drop.
      #
      # Returns a JSON representation of the Drop in a String.
      def to_json(state = nil)
        require 'json'
        JSON.generate(hash_for_json(state), state)
      end

      # Collects all the keys and passes each to the block in turn.
      #
      # block - a block which accepts one argument, the key
      #
      # Returns nothing.
      def each_key(&block)
        keys.each(&block)
      end

      def each(&block)
        each_key.each do |key|
          yield key, self[key]
        end
      end

      def merge(other, &block)
        self.dup.tap do |me|
          if block.nil?
            me.merge!(other)
          else
            me.merge!(other, block)
          end
        end
      end

      def merge!(other)
        other.each_key do |key|
          if block_given?
            self[key] = yield key, self[key], other[key]
          else
            if Utils.mergable?(self[key]) && Utils.mergable?(other[key])
              self[key] = Utils.deep_merge_hashes(self[key], other[key])
              next
            end

            self[key] = other[key] unless other[key].nil?
          end
        end
      end
    end
  end
end
