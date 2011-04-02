require 'active_record'
require 'rails_admin/config/sections/list'
require 'rails_admin/abstract_object'

module RailsAdmin
  module Adapters
    module ActiveRecord
      def self.polymorphic_parents(name)
        unless @polymorphic_parents
          @polymorphic_parents = {}
          RailsAdmin::AbstractModel.all.each do |abstract_model|
            abstract_model.polymorphic_has_many_associations.each do |association|
              (@polymorphic_parents[association[:options][:as]] ||= []) << abstract_model
            end
          end
        end
        @polymorphic_parents[name.to_sym]
      end

      def get(id)
        if object = model.find_by_id(id)
          RailsAdmin::AbstractObject.new object
        else
          nil
        end
      end

      def get_bulk(ids, scope = nil)
        scope ||= model
        scope.find_all_by_id(ids)
      end

      def count(options = {}, scope = nil)
        scope ||= model
        Rails.cache.fetch("#{model.table_name}_count", :expires_in => 3600) do
          scope.count(options.reject{|key, value| [:sort, :sort_reverse].include?(key)})
        end
      end

      def first(options = {}, scope = nil)
        scope ||= model
        scope.first(merge_order(options))
      end

      def all(options = {}, scope = nil)
        scope ||= model
        scope.all(merge_order(options))
      end

      def paginated(options = {}, scope = nil)
        page = options.delete(:page) || 1
        per_page = options.delete(:per_page) || RailsAdmin::Config::Sections::List.default_items_per_page

        page_count = (count(options, scope).to_f / per_page).ceil

        options.merge!({
          :limit => per_page,
          :offset => (page - 1) * per_page
        })

        [page_count, all(options, scope)]
      end

      def create(params = {})
        model.create(params)
      end

      def new(params = {})
        RailsAdmin::AbstractObject.new(model.new)
      end

      def destroy(ids, scope = nil)
        scope ||= model
        scope.destroy_all(:id => ids)
      end

      def destroy_all!
        model.all.each do |object|
          object.destroy
        end
      end

      def has_and_belongs_to_many_associations
        associations.select do |association|
          association[:type] == :has_and_belongs_to_many
        end
      end

      def has_many_associations
        associations.select do |association|
          association[:type] == :has_many
        end
      end

      def has_one_associations
        associations.select do |association|
          association[:type] == :has_one
        end
      end

      def belongs_to_associations
        associations.select do |association|
          association[:type] == :belongs_to
        end
      end

      def associations
        model.reflect_on_all_associations.map do |association|
          {
            :name => association.name,
            :pretty_name => association.name.to_s.gsub('_', ' ').capitalize,
            :type => association.macro,
            :parent_model => association_parent_model_lookup(association),
            :parent_key => association_parent_key_lookup(association),
            :child_model => association_child_model_lookup(association),
            :child_key => association_child_key_lookup(association),
            :options => association.options,
          }
        end
      end

      def polymorphic_has_many_associations
        has_many_associations.select do |association|
          association[:options][:as]
        end
      end

      def properties
        model.columns.map do |property|
          {
            :name => property.name.to_sym,
            :pretty_name => property.name.to_s.gsub('_', ' ').capitalize,
            :type => property.type,
            :length => property.limit,
            :nullable? => property.null,
            :serial? => property.primary,
          }
        end
      end

      def model_store_exists?
        model.table_exists?
      end

      private

      def merge_order(options)
        @sort ||= options.delete(:sort) || "id"
        @sort_order ||= options.delete(:sort_reverse) ? "asc" : "desc"
        options.merge(:order => "#{@sort} #{@sort_order}")
      end

      def association_parent_model_lookup(association)
        case association.macro
        when :belongs_to
          if association.options[:polymorphic]
            RailsAdmin::Adapters::ActiveRecord.polymorphic_parents(association.name)
          else
            association.klass
          end
        when :has_one, :has_many, :has_and_belongs_to_many
          association.active_record
        else
          raise "Unknown association type: #{association.macro.inspect}"
        end
      end

      def association_parent_key_lookup(association)
        [:id]
      end

      def association_child_model_lookup(association)
        case association.macro
        when :belongs_to
          association.active_record
        when :has_one, :has_many, :has_and_belongs_to_many
          association.klass
        else
          raise "Unknown association type: #{association.macro.inspect}"
        end
      end

      def association_child_key_lookup(association)
        case association.macro
        when :belongs_to
          [association.options[:foreign_key] || "#{association.name}_id".to_sym]
        when :has_one, :has_many, :has_and_belongs_to_many
          [association.primary_key_name.to_sym]
        else
          raise "Unknown association type: #{association.macro.inspect}"
        end
      end
    end
  end
end
