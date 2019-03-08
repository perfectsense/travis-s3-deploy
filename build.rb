#!/usr/bin/ruby -w

require 'rexml/document'
include REXML
require 'optparse'
require 'time'

$stdout.sync = true

LOCAL_M2_DIR = ENV['HOME'] + "/.m2/repository/"

ENV["MAVEN_OPTS"] = "#{ENV["MAVEN_OPTS"]} -Xmx6g"

OPTIONS = {}
OPTIONS[:frontend_files] = "styleguide package.json gulpfile.js yarn.lock .npmrc"
OPTIONS[:site_module_path] = "site"
OPTIONS[:themes_module_path] = "themes"
OPTIONS[:frontend_module_path] = "frontend"
OPTIONS[:parent_module_path] = "parent"
OPTIONS[:maven_options] = "-B -Plibrary"
OPTIONS[:maven_repo_stale_date] = Time.now - (86400*30)  # 30 days in seconds

# Represents a Maven artifact, where the path is optional.
class MavenArtifact
  attr_accessor :group_id, :artifact_id, :version, :packaging, :path

  def initialize(group_id, artifact_id, version, packaging, path)
    @group_id = group_id
    @artifact_id = artifact_id
    @version = version
    @packaging = packaging
    @path = path
  end

  def local_repo_unversioned_path
    LOCAL_M2_DIR + File.join(group_id.to_s.gsub(/\./, "/"), artifact_id.to_s)
  end

  def local_repo_path
    LOCAL_M2_DIR + File.join(group_id.to_s.gsub(/\./, "/"), artifact_id.to_s, \
      version.to_s)
  end

  def local_path(ext)
    f = File.join(local_repo_path.to_s, artifact_id.to_s + "-" + version.to_s + ext)
    f if File.exist?(f)
  end

  def local_pom_path
    local_path(".pom")
  end

  def local_war_path
    local_path(".war")
  end

  def local_jar_path
    local_path(".jar")
  end

  def local_classes_jar_path
    local_path("-classes.jar")
  end

  def all_local_files
    [local_pom_path, local_war_path, local_jar_path, local_classes_jar_path].select { |p| p != nil }
  end

  def to_s
    "#{@group_id}:#{@artifact_id}:#{@version}"
  end
end

# Semantic Version, mostly-ish
class SemVersion

  attr_accessor :major, :minor, :patch

  def initialize(version)

    if version.respond_to?("major")
      @major = version.major
      @minor = version.minor
      @patch = version.patch
    else
      # parse version string
      version_parts = version.split(/\./, 3)

      if version_parts.length > 0
        @major = version_parts[0]
      else
        @major = '0'
      end

      if version_parts.length > 1
        @minor = version_parts[1]
      else
        @minor = nil
      end

      if version_parts.length > 2
        @patch = version_parts[2]
      else
        @patch = nil
      end

    end
  end

  def to_s
    "#{@major}.#{@minor}.#{@patch}"
  end

  def major_number
    if @major == nil
      nil
    else
      @major.to_i
    end
  end

  def minor_number
    if @minor == nil
      nil
    else
      @minor.to_i
    end
  end

  def patch_number
    if @patch == nil
      nil
    else
      @patch.to_i
    end
  end

end

# Only print message if executed with --verbose
def debug_log(message)
  puts message if OPTIONS[:verbose]
end

CURRENT_TRAVIS = {activity: nil, start_time: nil, timer_id: nil}

def travis_start(activity)
  if CURRENT_TRAVIS[:activity] != nil
    raise "Nested travis_start is not supported!"
  end
  start_time = Time.now.to_f * 1000000000
  CURRENT_TRAVIS[:activity] = activity
  CURRENT_TRAVIS[:timer_id] = ([start_time].pack "I").to_s.each_byte.map { |b| b.to_s(16) }.join
  CURRENT_TRAVIS[:start_time] = start_time.to_i
  puts "travis_fold:start:#{CURRENT_TRAVIS[:activity]}"
  puts "travis_time:start:#{CURRENT_TRAVIS[:timer_id]}"
end

def travis_end
  if CURRENT_TRAVIS[:activity] == nil
    raise "Can't travis_end without travis_start!"
  end
  end_time = (Time.now.to_f * 1000000000).to_i
  duration = end_time - CURRENT_TRAVIS[:start_time]
  puts "travis_time:end:#{CURRENT_TRAVIS[:timer_id]}:start=#{CURRENT_TRAVIS[:start_time]},finish=#{end_time},duration=#{duration}"
  puts "travis_fold:end:#{CURRENT_TRAVIS[:activity]}"
  CURRENT_TRAVIS[:activity] = nil
  CURRENT_TRAVIS[:timer_id] = nil
  CURRENT_TRAVIS[:start_time] = nil
end

# Finds the element targeted by the given XPath expression for the pom.xml of
# the given module_path and returns the text value of the first result.
def maven_xpath(module_path, expr)
  if File.exist? "#{module_path}/pom.xml"
    list = maven_xpath_list(module_path, expr)
    list.each do |item|
      return item
    end
  end
  nil
end

# Finds the elements targeted by the given XPath expression for the pom.xml of
# the given module_path and returns the text values as an iterable.
def maven_xpath_list(module_path, expr)
  pomSrc = "#{module_path}/pom.xml"
  if File.exist? pomSrc
    xmlfile = File.new(pomSrc)
    xmldoc = Document.new(xmlfile)

    XPath.each(xmldoc, "#{expr}/text()")
  else
    return []
  end
end

# Calculates the Maven artifact info (groupId / artifactId / version) for the
# given module_paths. If only one path is given then only one MavenArtifact is
# returned, otherwise an iterable of the results is returned.
def maven_module_info(module_paths)

  if module_paths.respond_to?("each")
    modules = Array.new

    module_paths.each do |module_path|
      modules.push(maven_module_info(module_path))
    end

    modules
  else
    group_id = maven_xpath(module_paths, "/project/groupId")
    if group_id == nil
      group_id = maven_xpath(module_paths, "/project/parent/groupId")
    end
    artifact_id = maven_xpath(module_paths, "/project/artifactId")
    version = maven_xpath(module_paths, "/project/version")
    if version == nil
      version = maven_xpath(module_paths, "/project/parent/version")
    end
    packaging = maven_xpath(module_paths, "/project/packaging")
    if packaging == nil
      packaging = 'jar'
    end

    MavenArtifact.new(group_id, artifact_id, version, packaging, module_paths)
  end
end

# Gets the list of modules defined in the pom.xml at the given path. This
# function can optionally recurse down to sub-modules.
def maven_module_list(path, recurse = false)

  module_list = Array.new

  maven_xpath_list(path, "/project/modules/module").each do |name|

    module_list.push(name.to_s)

    if recurse
      maven_module_list("#{path}/#{name}", true).each do |name2|
        module_list.push("#{name}/#{name2}")
      end
    end
  end

  module_list
end

# For a given Maven artifact, checks maven local repository to see if the artifact already
# exists
def maven_cache_status(maven_artifact)

  maven_artifact = maven_module_info(maven_artifact) unless maven_artifact.respond_to?("group_id")

  debug_log "Looking for cached #{maven_artifact.to_s} . . ."
  cached = !maven_artifact.all_local_files.empty?

  if cached
    puts "#{maven_artifact.to_s} [CACHED]"

  else
    puts "#{maven_artifact.to_s} [BUILD]"
  end

  cached
end

# Fetches an array of maven module paths whose versions have not yet been
# deployed to maven local repository
def select_uncached_modules(all_modules, reactor_modules)

  new_modules = Array.new

  all_modules.each do |mod|
      new_modules.push(mod) unless maven_cache_status(mod) \
          or !reactor_modules.include? mod.path
  end

  new_modules
end

# Fetch an array of all mave module paths that are in the reactor
def select_reactor_modules(all_modules, reactor_modules)

  new_modules = Array.new

  all_modules.each do |mod|
      new_modules.push(mod) if reactor_modules.include? mod.path
  end

  new_modules
end

def system_stdout(command)
  puts "COMMAND: #{command}"
  system(command, out: $stdout, err: :out)
end

# Update the given pom_doc's project to the given version
def set_version(artifact, pom_doc, version)
  debug_log "#{artifact.group_id.to_s}:#{artifact.artifact_id.to_s}: Setting project version to #{version}"
  version_element = XPath.first(pom_doc, '/project/version')
  if version_element == nil
    project_element = XPath.first(pom_doc, '/project')
    version_element = Element.new("version", project_element)
  end
  version_element.text = version
end

# Update the given dependency version
def set_dependency_version(artifact, pom_doc, group_id, artifact_id, version)

  XPath.each(pom_doc, "//dependency | //parent") do |dep|
    dep_group_id = XPath.first(dep, "groupId/text()")

    dep_artifact_id = XPath.first(dep, "artifactId/text()")
    dep_version_elmt = XPath.first(dep, "version")

    if dep_group_id.to_s == group_id.to_s && dep_artifact_id.to_s == artifact_id.to_s && dep_version_elmt != nil
      debug_log "#{artifact.group_id.to_s}:#{artifact.artifact_id.to_s}: Setting #{group_id}:#{artifact_id} version to #{version}"
      dep_version_elmt.text = version
    end

  end

  XPath.each(pom_doc, "//[contains(text(), '#{artifact_id}-${project.version}')]") do |other|
    other.text = other.text.to_s.gsub('${project.version}', version)
  end

end

def update_versions(artifacts)

  artifacts.each do |artifact|
    article = artifact.path + '/pom.xml'
    if File.exist? article
      File.open(article) do |f|
        pom = Document.new(f)

        set_version(artifact, pom, artifact.version)
        for dependency in artifacts
          set_dependency_version(artifact, pom, dependency.group_id, dependency.artifact_id, dependency.version)
        end

        File.open(artifact.path + '/pom.xml', 'w') do |wf|
          formatter = REXML::Formatters::Default.new
          formatter.write(pom, wf)
        end
      end
    end
  end
end

# Generate a new version number for the given module_path using the given file paths
def versioned_maven_module(module_path, file_paths)
  file_paths_str = file_paths.respond_to?('each') ? file_paths.join(' ') : file_paths
  commit_count = `git rev-list --count HEAD -- #{file_paths_str}`.to_s.strip
  commit_hash = `git rev-list HEAD -- #{file_paths_str} | head -1`.to_s.strip[0, 6]
  artifact = maven_module_info(module_path)
  version = SemVersion.new(artifact.version.to_s)

  if (version.minor == nil)
    version.minor = '0'
  end

  artifact.version = version.major \
      + '.' + version.minor \
      + '.' + commit_count \
      + '-x' + commit_hash
  artifact
end

# Travis clones a shallow repo, unshallow it to get accurate commit counts
def unshallow_repo

  if File.exist?(`git rev-parse --git-dir`.to_s.strip + '/shallow')
    system_stdout('git fetch --unshallow')
  end

end


def test_option
  if OPTIONS[:skip_tests] || (OPTIONS[:skip_tests_if_pr] && ENV["TRAVIS_PULL_REQUEST"] != "false")
    "-Dmaven.test.skip=true"
  end
end

def mkdir_p(path)
  local_path = "."
  created = false
  for part in File.split(path)
    local_path = File.join(local_path, part)
    unless File.exist? local_path
      Dir.mkdir local_path
      created = true
    end
  end
  created
end

# Some integration tests require the frontend to be available in the
# ./frontend/target directory, so just to be safe unpack the cached artifacts
# into each target directory
def unpack_cached_artifacts(artifacts)
  for artifact in artifacts
    debug_log "Unpacking #{artifact.to_s}"
    classes_dir = File.join(artifact.path, "target", "classes")
    war_dir = File.join(artifact.path, "target", "#{artifact.artifact_id.to_s}-#{artifact.version.to_s}")

    if artifact.local_jar_path
      if mkdir_p classes_dir
        system_stdout "unzip -qo #{artifact.local_jar_path} -d #{classes_dir}"
      end
    end

    if artifact.local_classes_jar_path
      if mkdir_p classes_dir
        system_stdout "unzip -qo #{artifact.local_classes_jar_path} -d #{classes_dir}"
      end
    end

    if artifact.local_war_path
      if mkdir_p war_dir
        system_stdout "unzip -qo #{artifact.local_war_path} -d #{war_dir}"
      end
    end
  end
end

def cleanup_old_local_files(artifacts)
  puts "Removing Maven repository artifacts last modified before #{OPTIONS[:maven_repo_stale_date]}"
  for artifact in artifacts
    debug_log "LOCAL PATH: " + artifact.local_repo_unversioned_path
    local_versioned_path = artifact.local_repo_path
    Dir.glob(File.join(artifact.local_repo_unversioned_path.to_s, "**/*")) { |f|
      unless f.start_with? local_versioned_path
        unless File.directory? f
          debug_log "OLD PROJECT ARTIFACT, DELETING: " + f
          File.delete f
        end
      end
    }
  end
  Dir.glob(File.join(LOCAL_M2_DIR, "**/*")) { |f|
    unless File.directory? f
      to_delete = true
      for artifact in artifacts
        if f.start_with? artifact.local_repo_unversioned_path
          to_delete = false
        end
      end
      if File.mtime(f) > OPTIONS[:maven_repo_stale_date]
        to_delete = false
      end
      if to_delete
        debug_log "NOT PROJECT ARTIFACT, DELETING: " + f
        File.delete f
      end
    end
  }
  Dir.glob(File.join(LOCAL_M2_DIR, "**/*")).reverse { |f|
    if File.directory? f
      if (Dir.entries(f) - %w{ . .. }).empty?
        debug_log "EMPTY DIRECTORY, DELETING: " + f
        Dir.delete f
      end
    end
  }
end

def dependencies_ok(artifact)
  system("mvn dependency:resolve -pl '#{artifact.group_id}:#{artifact.artifact_id}'")
end

def install(build_artifacts, site_artifact)
  # remove the site artifact from build_artifacts. it's built separately
  build_artifacts = build_artifacts - [site_artifact]
  modules = build_artifacts.map{|a| "#{a.group_id}:#{a.artifact_id}"}.join(",")
  not_site = "!#{site_artifact.group_id}:#{site_artifact.artifact_id}"

  unless build_artifacts.empty?
    travis_start "build"
    system_stdout "mvn #{OPTIONS[:maven_options]} install -amd -pl '#{modules},#{not_site}' #{test_option}" or abort "Build failed!"
    travis_end
  end

  travis_start "build_site"
  system_stdout "mvn #{OPTIONS[:maven_options]} verify -amd -pl '#{site_artifact.group_id}:#{site_artifact.artifact_id}' #{test_option}" or abort "Build failed!"
  travis_end
end

def build

  travis_start "unshallow_repo"
  unshallow_repo
  travis_end

  travis_start "update_versions"
  # find all artifacts in the reactor
  reactor_artifacts = maven_module_list('.', true) + ['.']

  # Determine all version numbers
  site_module_path = OPTIONS[:site_module_path]
  themes_module_path = OPTIONS[:themes_module_path]
  frontend_module_path = OPTIONS[:frontend_module_path]
  parent_module_path = OPTIONS[:parent_module_path]
  frontend_files = OPTIONS[:frontend_files].split(" ") + [frontend_module_path]

  all_themes_files = Dir[themes_module_path + "/*.*"]
  theme_files = Dir[themes_module_path + "/*/pom.xml"].map{|x| x.gsub(/\/pom.xml$/, "")}
  module_dependency_files = ["pom.xml", parent_module_path] + frontend_files
  modules = Dir["*/pom.xml"].map{|x| x.gsub(/\/pom.xml$/, "")} - frontend_files \
      - [themes_module_path, site_module_path] - theme_files
  frontend_dependency_files = frontend_files + all_themes_files
  frontend_artifact = versioned_maven_module(frontend_module_path, frontend_files)
  themes_artifact = versioned_maven_module(themes_module_path, all_themes_files)
  # modules other than theme,site,frontend,aggregate versions change if those modules change
  modules_artifacts = modules.map{|m| versioned_maven_module(m, [m] + module_dependency_files)}
  # theme version changes if the theme or the root frontend files change
  themes_artifacts = theme_files.map{|m| versioned_maven_module(m, [m] + frontend_dependency_files)}
  # site version should change if anything in the entire repo changes
  site_artifact = versioned_maven_module(site_module_path, '.')
  # aggregate version only needs to change if the aggregate pom changes
  aggregate_artifact = versioned_maven_module('.', 'pom.xml')

  # Site artifact gets a special version number
  if ENV["TRAVIS_PULL_REQUEST"] && ENV["TRAVIS_PULL_REQUEST"] != "false"
    # 1.0-PR123
    site_artifact = maven_module_info(site_module_path)
    site_artifact_version = SemVersion.new(site_artifact.version.to_s)
    site_artifact.version = site_artifact_version.major.to_s + '.' + site_artifact_version.minor.to_s + "-PR" + ENV["TRAVIS_PULL_REQUEST"]

  elsif ENV["TRAVIS_BUILD_NUMBER"]
    # 1.0.87-xabc123f+45 where 87 is the number of commits,
    # abc123f is the commit sha, and 45 is the Travis build number
    site_artifact.version = site_artifact.version + "+" + ENV["TRAVIS_BUILD_NUMBER"]
  end

  # Set versions in all pom.xml files
  all_artifacts = [aggregate_artifact, site_artifact, frontend_artifact, \
      themes_artifact] + themes_artifacts + modules_artifacts
  update_versions(all_artifacts)

  # only build artifacts that aren't installed in the local maven repo
  build_artifacts = select_uncached_modules(all_artifacts, reactor_artifacts)
  cached_artifacts = all_artifacts - build_artifacts

  # last minute check to make sure all cached_artifacts are actually available
  if !dependencies_ok site_artifact
    # just build all modules
    build_artifacts = select_reactor_modules(all_artifacts, reactor_artifacts)
  end
  travis_end

  if build_artifacts.empty?
    puts "Nothing to do!"

  else

    travis_start "unpack_cached_artifacts"
    # unpack cached artifacts for integration tests
    unpack_cached_artifacts cached_artifacts
    travis_end

    # build and install the artifacts that need to be built
    install build_artifacts, site_artifact

    travis_start "cleanup_old_local_files"
    # clean up the .m2 cache or it'll get huge
    cleanup_old_local_files all_artifacts
    travis_end
  end

end

if __FILE__ == $0

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("--verbose", "Run verbosely") do |v|
      OPTIONS[:verbose] = v
    end

    opts.on("--skip-tests", "Skip Tests") do |v|
      OPTIONS[:skip_tests] = v
    end

    opts.on("--skip-tests-if-pr", "Skip Tests if this is a Github Pull Request in Travis") do |v|
      OPTIONS[:skip_tests_if_pr] = v
    end

    opts.on("--frontend-files=", "Frontend files; default is \"#{OPTIONS[:frontend_files]}\"") do |v|
      OPTIONS[:frontend_files] = v
    end

    opts.on("--site-module-path=", "Site module; default is \"#{OPTIONS[:site_module_path]}\"") do |v|
      OPTIONS[:site_module_path] = v
    end

    opts.on("--themes-module-path=", "Themes module; default is \"#{OPTIONS[:themes_module_path]}\"") do |v|
      OPTIONS[:themes_module_path] = v
    end

    opts.on("--frontend-module-path=", "Frontend module; default is \"#{OPTIONS[:frontend_module_path]}\"") do |v|
      OPTIONS[:frontend_module_path] = v
    end

    opts.on("--parent-module-path=", "Parent module [if different than aggregate]; default is \"#{OPTIONS[:parent_module_path]}\"") do |v|
      OPTIONS[:parent_module_path] = v
    end

    opts.on("--maven-options=", "Maven options; default is \"#{OPTIONS[:maven_options]}\"") do |v|
      OPTIONS[:maven_options] = v
    end

    opts.accept(Time) do |time|
      Time.strptime(time, "%F")
    end
    opts.on("--maven-stale-date=", Time, "Artifacts older than this in the Maven m2 repository will be removed (YYYY-MM-DD); default is \"#{OPTIONS[:maven_repo_stale_date].strftime("%F")}\" (30 days ago)") do |v|
      OPTIONS[:maven_repo_stale_date] = v
    end
  end.parse!

  build
end
