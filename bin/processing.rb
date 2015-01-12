#!/usr/bin/env jruby

exec("jruby #{__FILE__} #{ARGV.join(' ')}") if RUBY_PLATFORM != 'java'

require 'java'
require 'find'

# Provides classes and methods for Processing sketches
module Processing
  COMMAND_NAME = File.basename(__FILE__)

  if ARGV.size < 1
    puts "Usage: #{COMMAND_NAME} [sketchfile]"
    exit
  end

  SKETCH_FILE = ARGV[0]
  SKETCH_BASE = File.basename(SKETCH_FILE)
  SKETCH_DIR = File.dirname(SKETCH_FILE)

  unless FileTest.file?(SKETCH_FILE)
    puts "#{COMMAND_NAME}: Sketch file not found -- '#{SKETCH_FILE}'"
    exit
  end

  PROCESSING_ROOT = ENV['PROCESSING_ROOT'] || '/dummy'
  PROGRAMFILES = ENV['PROGRAMFILES'] || '/dummy'
  PROGRAMFILES_X86 = ENV['PROGRAMFILES(X86)'] || '/dummy'
  PROCESSING_LIBRARY_DIRS = [
    File.join(SKETCH_DIR, 'libraries'),
    File.expand_path('Documents/Processing/libraries', '~'),

    PROCESSING_ROOT,
    File.join(PROCESSING_ROOT, 'modes/java/libraries'),

    '/Applications/Processing.app/Contents/Java',
    '/Applications/Processing.app/Contents/Java/modes/java/libraries',

    File.join(PROGRAMFILES, 'processing-*'),
    File.join(PROGRAMFILES, 'processing-*/modes/java/libraries'),

    File.join(PROGRAMFILES_X86, 'processing-*'),
    File.join(PROGRAMFILES_X86, 'processing-*/modes/java/libraries'),

    'C:/processing-*',
    'C:/processing-*/modes/java/libraries'
  ].flat_map { |dir| Dir.glob(dir) }

  SKETCH_INSTANCES = []
  RELOAD_REQUEST = []
  WATCH_INTERVAL = 0.1

  # Loads the specified processing library
  def self.load_library(name)
    PROCESSING_LIBRARY_DIRS.each do |dir|
      return true if load_jar_files(File.join(dir, name, 'library'))
    end

    puts "#{COMMAND_NAME}: Library not found -- '#{name}'"
    false
  end

  # Loads all of the jar files in the specified directory
  def self.load_jar_files(dir)
    is_success = false

    if File.directory?(dir)
      Dir.glob(File.join(dir, '*.jar')).each do |jar|
        require jar
        is_success = true
        puts "#{COMMAND_NAME}: Jar file loaded -- #{File.basename(jar)}"
      end
      return true if is_success
    end

    false
  end

  # Reloads and restarts the sketch file
  def self.reload_sketch
    RELOAD_REQUEST[0] = true
  end

  # Starts the specified sketch instance
  def self.run_sketch(sketch, title = SKETCH_BASE)
    PApplet.run_sketch([title], sketch)
  end

  exit unless load_library 'core'
  java_import 'processing.core.PApplet'

  %w(
    FontTexture FrameBuffer LinePath LineStroker PGL PGraphics2D
    PGraphics3D PGraphicsOpenGL PShader PShapeOpenGL Texture
  ).each { |class_| java_import "processing.opengl.#{class_}" }

  # Base class for Processing sketch
  class SketchBase < PApplet
    %w(
      displayHeight displayWidth frameCount keyCode
      mouseButton mouseX mouseY pmouseX pmouseY
    ).each do |name|
      sc_name = name.split(/(?![a-z])(?=[A-Z])/).map(&:downcase).join('_')
      alias_method sc_name, name
    end

    def self.method_added(name)
      name = name.to_s
      if name.include?('_')
        lcc_name = name.split('_').map(&:capitalize).join('')
        lcc_name[0] = lcc_name[0].downcase
        alias_method lcc_name, name if lcc_name != name
      end
    end

    def initialize
      super
      SKETCH_INSTANCES << self
    end

    def frame_rate(fps = nil)
      return get_field_value('keyPressed') unless fps
      super(fps)
    end

    def key
      code = get_field_value('key')
      code < 256 ? code.chr : code
    end

    def key_pressed?
      get_field_value('keyPressed')
    end

    def mouse_pressed?
      get_field_value('mousePressed')
    end

    def get_field_value(name)
      java_class.declared_field(name).value(to_java(PApplet))
    end
  end

  INITIAL_FEATURES = $LOADED_FEATURES.dup
  INITIAL_CONSTANTS = Object.constants - [:INITIAL_CONSTANTS]

  loop do
    # create and run sketch
    Thread.new do
      begin
        Object::TOPLEVEL_BINDING.eval(File.read(SKETCH_FILE), SKETCH_FILE)
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts e
      end
    end

    # watch file changed
    execute_time = Time.now

    catch :loop do
      loop do
        sleep(WATCH_INTERVAL)

        Find.find(SKETCH_DIR) do |file|
          is_ruby = FileTest.file?(file) && File.extname(file) == '.rb'
          throw :loop if is_ruby && File.mtime(file) > execute_time
        end

        break unless RELOAD_REQUEST.empty?
      end
    end

    # restore execution environment
    SKETCH_INSTANCES.each do |sketch|
      sketch.frame.dispose
      sketch.dispose
    end

    SKETCH_INSTANCES.clear
    RELOAD_REQUEST.clear

    added_constants = Object.constants - INITIAL_CONSTANTS
    added_constants.each do |constant|
      Object.class_eval { remove_const constant }
    end

    added_features = $LOADED_FEATURES - INITIAL_FEATURES
    added_features.each { |feature| $LOADED_FEATURES.delete(feature) }

    java.lang.System.gc
  end
end
