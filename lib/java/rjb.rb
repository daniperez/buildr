require 'rjb'

# Equivalent to Java system properties.  For example:
#   ENV_JAVA['java.version']
#   ENV_JAVA['java.class.version']
ENV_JAVA = {}


# Buildr runs along side a JVM, using either RJB or JRuby.  The Java module allows
# you to access Java classes and create Java objects.
#
# Java classes are accessed as static methods on the Java module, for example:
#   str = Java.java.lang.String.new('hai!')
#   str.toUpperCase
#   => 'HAI!'
#   Java.java.lang.String.isInstance(str)
#   => true
#   Java.com.sun.tools.javac.Main.compile(args)
#
# The classpath attribute allows Buildr to add JARs and directories to the classpath,
# for example, we use it to load Ant and various Ant tasks, code generators, test
# frameworks, and so forth.
#
# When using an artifact specification, Buildr will automatically download and
# install the artifact before adding it to the classpath.
#
# For example, Ant is loaded as follows:
#   Java.classpath << 'org.apache.ant:ant:jar:1.7.0'
#
# Artifacts can only be downloaded after the Buildfile has loaded, giving it
# a chance to specify which remote repositories to use, so adding to classpath
# does not by itself load any libraries.  You must call Java.load before accessing
# any Java classes to give Buildr a chance to load the libraries specified in the
# classpath.
#
# When building an extension, make sure to follow these rules:
# 1. Add to the classpath when the extension is loaded (i.e. in module or class
#    definition), so the first call to Java.load anywhere in the code will include
#    the libraries you specify.
# 2. Call Java.load once before accessing any Java classes, allowing Buildr to
#    set up the classpath.
# 3. Only call Java.load when invoked, otherwise you may end up loading the JVM
#    with a partial classpath, or before all remote repositories are listed.
# 4. Check on a clean build with empty local repository.
module Java

  module Package #:nodoc:

    def method_missing(sym, *args, &block)
      raise ArgumentError, 'No arguments expected' unless args.empty?
      name = "#{@name}.#{sym}"
      return ::Rjb.import(name) if sym.to_s =~ /^[[:upper:]]/
      Java.send :__package__, name
    end

  end

  class << self

    # Returns the classpath, an array listing directories, JAR files and
    # artifacts.  Use when loading the extension to add any additional
    # libraries used by that extension.
    #
    # For example, Ant is loaded as follows:
    #   Java.classpath << 'org.apache.ant:ant:jar:1.7.0'
    def classpath
      @classpath ||= []
    end

    # Loads the JVM and all the libraries listed on the classpath.  Call this
    # method before accessing any Java class, but only call it from methods
    # used in the build, giving the Buildfile a chance to load all extensions
    # that append to the classpath and specify which remote repositories to use.
    def load
      return self unless @loaded
      unless RUBY_PLATFORM =~ /darwin/i
        home = ENV['JAVA_HOME'] or fail 'Are we forgetting something? JAVA_HOME not set.'
        tools = File.expand_path('lib/tools.jar', home)
        raise "I need tools.jar to compile, can't find it in #{home}/lib" unless File.exist?(tools)
        classpath << tools
      end
      cp = Buildr.artifacts(classpath).map(&:to_s).each { |path| file(path).invoke }
      java_opts = (ENV['JAVA_OPTS'] || ENV['JAVA_OPTIONS']).to_s.split
      ::Rjb.load cp.join(File::PATH_SEPARATOR), java_opts

      props = ::Rjb.import('java.lang.System').getProperties
      enum = props.propertyNames 
      while enum.hasMoreElements
        name = enum.nextElement.toString
        ENV_JAVA[name] = props.getProperty(name)
      end
      @loaded = true
      self
    end

    def method_missing(sym, *args, &block) #:nodoc:
      raise ArgumentError, 'No arguments expected' unless args.empty?
      name = sym.to_s
      return ::Rjb.import(name) if name =~ /^[[:upper:]]/
      __package__ name
    end

  private

    def __package__(name) #:nodoc:
      const = name.split('.').map { |part| part.gsub(/^./) { |char| char.upcase } }.join
      return Java.const_get(const) if Java.const_defined?(const)
      package = Module.new
      package.extend Package
      package.instance_variable_set :@name, name
      Java.const_set(const, package)
    end

  end

end
