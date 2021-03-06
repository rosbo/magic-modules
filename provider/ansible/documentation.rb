# Copyright 2017 Google Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'api/object'
require 'compile/core'
require 'provider/config'
require 'provider/core'
require 'provider/ansible/manifest'

module Provider
  module Ansible
    # Responsible for building out YAML documentation blocks.
    module Documentation
      # This is not a comprehensive list of unsafe characters.
      # Ansible's YAML linter is more forgiving than Ruby's.
      # A more restricted list of unsafe characters allows for more
      # human readable YAML.
      UNSAFE_CHARS = %w[: & #].freeze
      # Takes a long string and divides each string into multiple paragraphs,
      # where each paragraph is a properly indented multi-line bullet point.
      #
      # Example:
      #   - This is a paragraph
      #     that wraps under
      #     the bullet properly
      #   - This is the second
      #     paragraph.
      def bullet_lines(line, spaces)
        line.split(".\n").map { |paragraph| bullet_line(paragraph, spaces) }
      end

      # Takes in a string (representing a paragraph) and returns a multi-line
      # string, where each line is less than max_length characters long and all
      # subsequent lines are indented in by spaces characters
      #
      # Example:
      #   - This is a sentence
      #     that wraps under
      #     the bullet properly
      #
      #   - |
      #     This is a sentence
      #     that wraps under
      #     the bullet properly
      #     because of the :
      #     character
      def bullet_line(paragraph, spaces, multiline = true, add_period = true)
        # + 2 for "- " and a potential period at the end of the sentence.
        # Remove arbitrary newlines created by formatting in YAML files
        indented = indent(wrap_field(paragraph.tr("\n", ' '), spaces + 3), 2)

        if multiline && UNSAFE_CHARS.any? { |c| paragraph.include?(c) }
          indented = "- |\n" + indented
        else
          indented[0] = '-'
        end

        if add_period
          indented += '.' unless indented.end_with?('.')
        end

        indented
      end

      # Builds out a full YAML block for DOCUMENTATION
      # This includes the YAML for the property as well as any nested props
      def doc_property_yaml(prop, config, spaces)
        block = minimal_doc_block(prop, config, spaces)
        # Ansible linter does not support nesting options this deep.
        if prop.is_a?(Api::Type::NestedObject)
          block.concat(nested_doc(prop.properties, config, spaces))
        elsif prop.is_a?(Api::Type::Array) &&
              prop.item_type.is_a?(Api::Type::NestedObject)
          block.concat(nested_doc(prop.item_type.properties, config, spaces))
        else
          block
        end
      end

      # Builds out a full YAML block for RETURNS
      # This includes the YAML for the property as well as any nested props
      def return_property_yaml(prop, spaces)
        block = minimal_return_block(prop, spaces)
        if prop.is_a? Api::Type::NestedObject
          block.concat(nested_return(prop.properties, spaces))
        elsif prop.is_a?(Api::Type::Array) &&
              prop.item_type.is_a?(Api::Type::NestedObject)
          block.concat(nested_return(prop.item_type.properties, spaces))
        else
          block
        end
      end

      private

      # Returns formatted nested documentation for a set of properties.
      def nested_return(properties, spaces)
        block = [indent('contains:', 4)]
        block.concat(
          properties.map do |p|
            indent(return_property_yaml(p, spaces + 4), 8)
          end
        )
      end

      def nested_doc(properties, config, spaces)
        block = [indent('suboptions:', 4)]
        block.concat(
          properties.map do |p|
            indent(doc_property_yaml(p, config, spaces + 4), 8)
          end
        )
      end

      # Builds out the minimal YAML block for DOCUMENTATION
      def minimal_doc_block(prop, config, spaces)
        [
          minimal_yaml(prop, spaces),
          indent([
            "required: #{prop.required ? 'true' : 'false'}",
            ("type: bool" if prop.is_a? Api::Type::Boolean),
            ("aliases: [#{config['aliases'][prop.name].join(', ')}]" \
             if config['aliases']&.keys&.include?(prop.name)),
            (if prop.is_a? Api::Type::Enum
               [
                 'choices:',
                 "[#{prop.values.map { |x| quote_string(x.to_s) }.join(', ')}]"
               ].join(' ')
             end)
          ].compact, 4)
        ]
      end

      # Builds out the minimal YAML block for RETURNS
      def minimal_return_block(prop, spaces)
        type = python_type(prop)
        # Complex types only mentioned in reference to RETURNS YAML block
        # Complex types are nested objects traditionally, but arrays of nested
        # objects will be included to avoid linting errors.
        type = 'complex' if prop.is_a?(Api::Type::NestedObject)|| \
          (prop.is_a?(Api::Type::Array) && \
           prop.item_type.is_a?(Api::Type::NestedObject))
        [
          minimal_yaml(prop, spaces),
          indent([
                   'returned: success',
                   "type: #{type}"
                 ], 4)
        ]
      end

      # Builds out the minimal YAML block necessary for a property.
      # This block will need to have additional information appened
      # at the end.
      def minimal_yaml(prop, spaces)
        [
          "#{Google::StringUtils.underscore(prop.name)}:",
          indent(
            [
              'description:',
              # + 8 to compensate for name + description.
              indent(bullet_lines(prop.description, spaces + 8), 4)
            ], 4
          )
        ]
      end

      def autogen_notice_contrib
        ['Please read more about how to change this file at',
         'https://www.github.com/GoogleCloudPlatform/magic-modules']
      end
    end
  end
end
