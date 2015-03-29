require 'find'

require_relative 'config'

module SketchRunner
  @@system_requests = []
  @@sketch_instances = []

  def self.add_command(command)
    @@system_requests << command
  end

  def self.add_sketch_instance(sketch)
    @@sketch_instances << sketch
  end

  def self.run_sketch
    $PROGRAM_NAME = ARGV.shift

    initial_features = $LOADED_FEATURES.dup
    initial_constants = Object.constants

    loop do
      puts '****** START SKETCH ******'

      Thread.new do
        begin
          Object::TOPLEVEL_BINDING.eval(File.read(SKETCH_FILE), SKETCH_FILE)
        rescue Exception => e
          puts e
        end
      end

      # watch file changed
      execute_time = Time.now

      catch :break_loop do
        loop do
          @@system_requests.each do |request|
            case request[:command]
            when :topmost
              sketch = request[:sketch]
              sketch.frame.set_always_on_top(true)

              is_always_on_top = sketch.frame.is_always_on_top
              @@system_requests.delete(request) if is_always_on_top
            when :pos
              sketch = request[:sketch]
              pos_x, pos_y = request[:pos]
              sketch.frame.set_location(pos_x, pos_y)

              cur_pos = sketch.frame.get_location
              is_pos_set = cur_pos.x == pos_x && cur_pos.y == pos_y
              @@system_requests.delete(request) if is_pos_set
            when :reload
              throw :break_loop
            end
          end

          Find.find(SKETCH_DIR) do |file|
            is_ruby = FileTest.file?(file) && File.extname(file) == '.rb'
            throw :break_loop if is_ruby && File.mtime(file) > execute_time
          end

          sleep(WATCH_INTERVAL)
        end
      end

      # restore execution environment
      SKETCH_INSTANCES.each do |sketch|
        sketch.frame.dispose
        sketch.dispose
      end

      SKETCH_INSTANCES.clear
      @@system_requests.clear

      added_constants = Object.constants - initial_constants
      added_constants.each do |constant|
        Object.class_eval { remove_const constant }
      end

      added_features = $LOADED_FEATURES - initial_features
      added_features.each { |feature| $LOADED_FEATURES.delete(feature) }

      java.lang.System.gc
    end
  end

  private_class_method :run_sketch

  run_sketch
end
