class Cookbook < ActiveRecord::Base
  include PgSearch

  scope :with_name, ->(name) { where('lower(name) = ?', name.to_s.downcase) }
  scope :recently_updated, -> { where('updated_at > ?', Time.now - 2.weeks) }

  scope :ordered_by, lambda { |ordering|
    order({
      'recently_updated' => 'updated_at DESC',
      'recently_added' => 'created_at DESC',
      'most_downloaded' => 'download_count DESC',
      'most_followed' => 'cookbook_followers_count DESC'
    }.fetch(ordering, 'name ASC'))
  }

  # Search
  # --------------------
  pg_search_scope(
    :search,
    against: {
      name: 'A',
      description: 'B',
      maintainer: 'D'
    },
    associated_against: {
      category: :name
    },
    using: {
      tsearch: { prefix: true, dictionary: 'english' }
    }
  )

  # Callbacks
  # --------------------
  before_validation :copy_name_to_lowercase_name

  # Associations
  # --------------------
  has_many :cookbook_versions, -> { order(id: :desc) }, dependent: :destroy
  has_many :cookbook_followers, dependent: :destroy
  has_one :latest_cookbook_version, -> { order(id: :desc) }, class_name: 'CookbookVersion'
  belongs_to :category
  belongs_to :owner, class_name: 'User', foreign_key: 'user_id'
  has_many :cookbook_collaborators
  has_many :collaborators, through: :cookbook_collaborators, source: :user

  # Validations
  # --------------------
  validates :name, presence: true, uniqueness: { case_sensitive: false }, format: /\A[\w_-]+\z/i
  validates :lowercase_name, presence: true, uniqueness: true
  validates :maintainer, presence: true
  validates :description, presence: true
  validates :cookbook_versions, presence: true
  validates :category, presence: true
  validates :source_url, url: {
    allow_blank: true,
    allow_nil: true
  }
  validates :issues_url, url: {
    allow_blank: true,
    allow_nil: true
  }

  #
  # Returns the name of the +Cookbook+ parameterized.
  #
  # @return [String] the name of the +Cookbook+ parameterized
  #
  def to_param
    name.parameterize
  end

  #
  # Return the specified +CookbookVersion+. Raises an
  # +ActiveRecord::RecordNotFound+ if the version does not exist. The first line
  # of the method translates the version from a parameter friendly verison
  # (2_0_1) to a dot version (2.0.1).
  #
  # @example
  #   cookbook.get_version!("1_0_0")
  #   cookbook.get_version!("latest")
  #
  # @param version [String] the version of the Cookbook to find. Pass in
  #                         'latest' to return the latest version of the
  #                         cookbook.
  #
  # @return [CookbookVersion] the +CookbookVersion+ with the version specified
  #
  def get_version!(version)
    version.gsub!(/_/, '.')

    if version == 'latest'
      latest_cookbook_version
    else
      cookbook_versions.find_by!(version: version)
    end
  end

  #
  # Saves a new version of the cookbook as specified by the given metadata and
  # tarball
  #
  # @raise [ActiveRecord::RecordInvalid] if the new version fails validation
  # @raise [ActiveRecord::RecordNotUnique] if the new version is a duplicate of
  #   an existing version for this cookbook
  #
  # @return [TrueClass]
  #
  # @param metadata [CookbookUpload::Metadata] the cookbook metadata
  # @param tarball [File] the cookbook artifact
  #
  def publish_version!(metadata, tarball, readme)
    dependency_names = metadata.dependencies.keys
    existing_cookbooks = Cookbook.where(name: dependency_names)

    transaction do
      self.maintainer = metadata.maintainer
      self.description = metadata.description

      cookbook_version = cookbook_versions.build(
        cookbook: self,
        license: metadata.license,
        version: metadata.version,
        tarball: tarball,
        readme: readme.contents,
        readme_extension: readme.extension
      )

      save!

      metadata.platforms.each do |name, version_constraint|
        cookbook_version.supported_platforms.create!(
          name: name,
          version_constraint: version_constraint
        )
      end

      metadata.dependencies.each do |name, version_constraint|
        cookbook_version.cookbook_dependencies.create!(
          name: name,
          version_constraint: version_constraint,
          cookbook: existing_cookbooks.find { |c| c.name == name }
        )
      end
    end

    CookbookNotifyWorker.perform_async(id)

    true
  end

  #
  # Returns true if the user passed follows the cookbook.
  #
  # @return [TrueClass]
  #
  # @param user [User]
  #
  def followed_by?(user)
    cookbook_followers.where(user: user).any?
  end

  #
  # Returns the platforms supported by the latest version of this cookbook.
  #
  # @return [Array<SupportedVersion>]
  #
  def supported_platforms
    latest_cookbook_version.supported_platforms
  end

  #
  # Returns the dependencies of the latest version of this cookbook.
  #
  # @return [Array<CookbookDependency>]
  #
  def cookbook_dependencies
    latest_cookbook_version.cookbook_dependencies
  end

  private

  #
  # Populates the +lowercase_name+ attribute with the lowercase +name+
  #
  # This exists until Rails schema dumping supports Posgres's expression
  # indices, which would allow us to create an index on LOWER(name). To do that
  # now, we'd have to use the raw SQL schema dumping functionality, which is
  # less-than ideal
  #
  def copy_name_to_lowercase_name
    self.lowercase_name = name.to_s.downcase
  end
end
