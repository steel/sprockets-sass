require "sass/importers/base"
require "pathname"

module Sprockets
  module Sass
    class Importer < ::Sass::Importers::Base
      GLOB = /\*|\[.+\]/
      
      # Reference to the Sprockets context
      attr_reader :context
      
      # 
      def initialize(context)
        @context = context
      end
      
      # @see Sass::Importers::Base#find_relative
      def find_relative(path, base_path, options)
        if path =~ GLOB
          engine_from_glob(path, base_path, options)
        else
          engine_from_path(path, base_path, options)
        end
      end
      
      # @see Sass::Importers::Base#find
      def find(path, options)
        engine_from_path(path, nil, options)
      end

      # @see Sass::Importers::Base#mtime
      def mtime(path, options)
        if pathname = resolve(path)
          pathname.mtime
        end
      rescue Errno::ENOENT
        nil
      end

      # @see Sass::Importers::Base#key
      def key(path, options)
        path = Pathname.new(path)
        ["#{self.class.name}:#{path.dirname.expand_path}", path.basename]
      end

      # @see Sass::Importers::Base#to_s
      def to_s
        "#{self.class.name}:#{context.pathname}"
      end
      
      protected
      
      # Create a Sass::Engine from the given path.
      def engine_from_path(path, base_path, options)
        pathname = resolve(path, base_path) or return nil
        context.depend_on pathname
        ::Sass::Engine.new evaluate(pathname), options.merge(
          :filename => pathname.to_s,
          :syntax   => syntax(pathname),
          :importer => self
        )
      end
      
      # Create a Sass::Engine that will handle importing
      # a glob of files.
      def engine_from_glob(glob, base_path, options)
        imports = resolve_glob(glob, base_path).inject("") do |imports, path|
          context.depend_on path
          relative_path = path.relative_path_from Pathname.new(context.root_path)
          imports << %(@import "#{relative_path}";\n)
        end
        return nil if imports.empty?
        ::Sass::Engine.new imports, options.merge(
          :filename => base_path.to_s,
          :syntax   => :scss,
          :importer => self
        )
      end
      
      # Finds an asset from the given path. This is where
      # we make Sprockets behave like Sass, and import partial
      # style paths.
      def resolve(path, base_path)
        path = Pathname.new(path) unless path.is_a?(Pathname)

        possible_files(path, base_path).each do | file|
          context.resolve(file) { |found| return found if context.asset_requirable?(found) }
        end

        nil
      end

      def possible_files(path, base_path)
        base_path = Pathname.new(base_path) unless base_path.is_a?(Pathname)
        paths = []

        # Check relative path
        unless path.to_s =~ /^\.+/
          paths << "./#{path}"

          # Maybe this file exists as a relative partial
          unless path.basename.to_s =~ /^_/
            paths << ("./" + path.dirname.join("_#{path.basename}").to_s)
          end
        end

        # Check root relative path
        unless path.to_s =~ /^\//
          relative_path = Pathname.new(base_path.dirname).relative_path_from Pathname.new(context.root_path)
          relative_path = relative_path.join path
          paths << relative_path

          # Logical partial
          unless relative_path.basename.to_s =~ /^_/
            paths << relative_path.dirname.join("_#{relative_path.basename}")
          end
        end

        # Look for the normal path
        paths << path
        
        # Then look for the partial-style version
        unless path.basename.to_s =~ /^_/
          paths << path.dirname.join("_#{path.basename}")
        end

        paths
      end
      
      # Finds all of the assets using the given glob.
      def resolve_glob(glob, base_path)
        base_path      = Pathname.new(base_path)
        path_with_glob = base_path.dirname.join(glob).to_s
        
        Pathname.glob(path_with_glob).sort.select do |path|
          path != context.pathname && context.asset_requirable?(path)
        end
      end
      
      # Returns the Sass syntax of the given path.
      def syntax(path)
        path.to_s.include?(".sass") ? :sass : :scss
      end
      
      # Returns the string to be passed to the Sass engine. We use
      # Sprockets to process the file, but we remove any Sass processors
      # because we need to let the Sass::Engine handle that.
      def evaluate(path)
        processors = context.environment.attributes_for(path).processors.dup
        processors.delete_if { |processor| processor < Tilt::SassTemplate }
        context.evaluate(path, :processors => processors)
      end
    end
  end
end
