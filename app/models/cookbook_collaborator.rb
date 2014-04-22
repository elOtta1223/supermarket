class CookbookCollaborator < ActiveRecord::Base
  # Associations
  # --------------------
  belongs_to :cookbook
  belongs_to :user

  # Validations
  # --------------------
  validates :cookbook, presence: true
  validates :user, presence: true
  validates :cookbook_id, uniqueness: { scope: :user_id }

  #
  # Returns the +CookbookCollaborator+ for the given +Cookbook+ and +User+
  #
  # @param cookbook [Cookbook] the cookbook
  # @param user [User] the user
  #
  # @return [CookbookCollaborator]
  #
  def self.with_cookbook_and_user(cookbook, user)
    where(cookbook_id: cookbook.id, user_id: user.id).first
  end
end
