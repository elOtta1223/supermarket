require 'open-uri'
require 'rubygems/package'
require 'foodcritic'
require 'mixlib/archive'

class CookbookArtifact
  #
  # Accessors
  #
  attr_accessor :url, :job_id, :work_dir

  #
  # Initializes a +CookbookArtifact+ downloading and unarchiving the
  # artifact from the given url.
  #
  # @param [String] the url where the artifact lives
  # @param [String] the id of the job in charge of processing the artifact
  #
  def initialize(url, jid)
    @url = url
    @job_id = jid || 'nojobid'
    @work_dir = File.join(Dir.tmpdir, job_id)
  end

  #
  # downloads and untars a cookbook to the work_dir
  #
  def prep
    downloaded_tarball = download
    tar = Mixlib::Archive.new(downloaded_tarball.path)
    tar.extract(work_dir, perms: false, ignore: /^\.$/)
  end

  #
  # Runs FoodCritic against an artifact.
  #
  # @return [Boolean] whether or not FoodCritic passed
  # @return [String] the would be command line out from FoodCritic
  #
  def criticize
    prep

    args = [work_dir, "-f #{ENV['FIERI_FOODCRITIC_FAIL_TAGS']}"]
    ENV['FIERI_FOODCRITIC_TAGS'].split.each do |tag|
      args.push("-t #{tag}")
    end if ENV['FIERI_FOODCRITIC_TAGS']
    cmd = FoodCritic::CommandLine.new(args)
    result, _status = FoodCritic::Linter.run(cmd)
    [result.to_s, result.failed?]
  end

  #
  # Removes the unarchived directory returns nil if the directory
  # doesn't exist.
  #
  # @return [Fixnum] the status code from the operation
  #
  def cleanup
    FileUtils.remove_dir(work_dir, force: false)
  end

  private

  #
  # Downloads an artifact from a url and writes it to the filesystem.
  #
  # @return [Tempfile] the artifact
  #
  def download
    File.open(Tempfile.new('archive'), 'wb') do |saved_file|
      open(url, 'rb') do |read_file|
        saved_file.write(read_file.read)
      end
      saved_file
    end
  end
end
