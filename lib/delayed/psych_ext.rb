if defined?(ActiveRecord)
  class ActiveRecord::Base
    # serialize to YAML
    def encode_with(coder)
      coder["attributes"] = @attributes
      coder.tag = ['!ruby/ActiveRecord', self.class.name].join(':')
    end
  end
end

class Delayed::PerformableMethod
  # serialize to YAML
  def encode_with(coder)
    coder.map = {
      "object" => object,
      "method_name" => method_name,
      "args" => args
    }
  end
end

module Psych
  module Visitors
    class ToRuby
      def visit_Psych_Nodes_Mapping_with_class(object)
        return revive(Psych.load_tags[object.tag], object) if Psych.load_tags[object.tag]

        case object.tag
        when /^!ruby\/ActiveRecord:(.+)$/
          klass = resolve_class($1)
          payload = Hash[*object.children.map { |c| accept c }]
          id = payload["attributes"][klass.primary_key]
          begin
            klass.unscoped.find(id)
          rescue ActiveRecord::RecordNotFound
            raise Delayed::DeserializationError
          end
        when /^!ruby\/Mongoid:(.+)$/
          klass = resolve_class($1)
          payload = Hash[*object.children.map { |c| accept c }]
          begin
            klass.find(payload["attributes"]["_id"])
          rescue Mongoid::Errors::DocumentNotFound
            raise Delayed::DeserializationError
          end
        when /^!ruby\/DataMapper:(.+)$/
          klass = resolve_class($1)
          payload = Hash[*object.children.map { |c| accept c }]
          begin
            primary_keys = klass.properties.select { |p| p.key? }
            key_names = primary_keys.map { |p| p.name.to_s }
            klass.get!(*key_names.map { |k| payload["attributes"][k] })
          rescue DataMapper::ObjectNotFoundError
            raise Delayed::DeserializationError
          end
        else
          visit_Psych_Nodes_Mapping_without_class(object)
        end
      end
      alias_method_chain :visit_Psych_Nodes_Mapping, :class

      def resolve_class_with_constantize(klass_name)
        klass_name.constantize
      rescue
        resolve_class_without_constantize(klass_name)
      end
      alias_method_chain :resolve_class, :constantize
    end
  end
end
