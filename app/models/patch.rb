# frozen_string_literal: true

class Patch < ActiveRecord::Base
  has_many :patch_ratings, dependent: :destroy
  has_many :patch_claims, dependent: :destroy
  has_many :patch_claim_logs, dependent: :destroy
  belongs_to :committer, class_name: "User", foreign_key: "committer_user_id", optional: true
  belongs_to :resolved_by, class_name: "User", foreign_key: "resolved_by_id", optional: true

  before_validation :normalize_commit_hash

  validates :commit_hash, presence: true
  validates :commit_hash, uniqueness: { case_sensitive: false }
  validates :commit_hash,
            format: {
              with: /\A[0-9a-f]{7,40}\z/,
              message: "must be a valid git commit hash",
            }
  validates :title, presence: true
  validates :resolution_status, inclusion: { in: %w[fixed invalid], allow_nil: true }
  validate :changeset_url_valid_for_fixed

  private def normalize_commit_hash
    self.commit_hash = commit_hash&.downcase&.strip
  end

  private def changeset_url_valid_for_fixed
    return unless resolution_status == "fixed"
    if resolution_changeset_url.blank?
      errors.add(:resolution_changeset_url, "is required when resolving as fixed")
    elsif !self.class.valid_changeset_url?(resolution_changeset_url)
      errors.add(:resolution_changeset_url, "must be a valid HTTP or HTTPS URL")
    end
  end

  def self.valid_changeset_url?(url)
    return false if url.blank?
    uri = URI.parse(url.to_s.strip)
    (uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  public

  scope :active, -> { where(active: true) }
  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :by_popularity, -> { order(Arel.sql("(useful_count + not_useful_count) DESC")) }
  scope :by_useful_ratio,
        -> do
          order(
            Arel.sql(
              "CASE WHEN (useful_count + not_useful_count) > 0 THEN useful_count::float / (useful_count + not_useful_count) ELSE 0 END DESC",
            ),
          )
        end
  scope :most_controversial,
        -> { order(Arel.sql("ABS(useful_count - not_useful_count) ASC, (useful_count + not_useful_count) DESC")) }
  scope :authored_by, ->(user) { user ? where(committer_user_id: user.id) : none }
  scope :by_committer, ->(username) { where(committer_github_username: username) }
  scope :by_github_id, ->(github_id) { where(committer_github_id: github_id) }
  scope :claimed_by, ->(user) { joins(:patch_claims).where(patch_claims: { user_id: user.id }) }
  scope :resolved_by, ->(user) { where(resolved_by_id: user.id) }

  def useful_ratio
    total = useful_count + not_useful_count
    return 0.0 if total.zero?
    (useful_count.to_f / total * 100).round(1)
  end

  def github_commit_url
    repo = github_repo_path
    "https://github.com/#{repo}/commit/#{commit_hash}"
  end

  def github_repo_path
    return "discourse/discourse" if repository.blank?

    # Parse repository field like "discourse (main)" or "discourse-ai"
    repo_name = repository.split("(").first.strip
    repo_name = "discourse" if repo_name == "discourse"

    "discourse/#{repo_name}"
  end

  def resolved?
    resolved_at.present?
  end

  def resolve!(user:, status:, notes: nil, changeset_url: nil)
    transaction do
      claim_user_ids = patch_claims.pluck(:user_id)
      if claim_user_ids.present?
        now = Time.current
        log_records =
          claim_user_ids.map do |user_id|
            {
              patch_id: id,
              user_id: user_id,
              action: "unclaimed",
              notes: "auto: patch resolved as #{status}",
              created_at: now,
              updated_at: now,
            }
          end
        PatchClaimLog.insert_all(log_records)
        patch_claims.delete_all
      end

      update!(
        resolved_at: Time.current,
        resolved_by_id: user.id,
        resolution_status: status,
        resolution_notes: notes,
        resolution_changeset_url: changeset_url,
      )
    end
  end

  def unresolve!
    update!(
      resolved_at: nil,
      resolved_by_id: nil,
      resolution_status: nil,
      resolution_notes: nil,
      resolution_changeset_url: nil,
    )
  end

  def claimed_by?(user)
    return false unless user
    patch_claims.exists?(user_id: user.id)
  end

  def claim_for(user, notes: nil)
    transaction do
      patch_claims.create!(user: user, notes: notes)
      patch_claim_logs.create!(user: user, action: "claimed", notes: notes)
    end
  end

  def unclaim_for(user)
    transaction do
      removed = patch_claims.where(user: user).delete_all
      patch_claim_logs.create!(user: user, action: "unclaimed") if removed > 0
    end
  end

  def match_committer_to_user!
    return if committer_user_id.present?

    # Try GitHub ID match first (most reliable)
    if committer_github_id.present?
      account =
        UserAssociatedAccount.find_by(
          provider_name: "github",
          provider_uid: committer_github_id.to_s,
        )

      if account&.user_id
        update(committer_user_id: account.user_id)
        return
      end
    end

    # Try email match
    if committer_email.present?
      user = User.find_by_email(committer_email)
      if user
        update(committer_user_id: user.id)
        return
      end
    end

    # Try GitHub username match via user_associated_accounts
    if committer_github_username.present?
      account =
        UserAssociatedAccount
          .where(provider_name: "github")
          .where("info->>'nickname' = ?", committer_github_username)
          .first

      update(committer_user_id: account.user_id) if account&.user_id
    end
  end

  def rated_by?(user)
    return false unless user
    patch_ratings.exists?(user_id: user.id)
  end

  def user_rating(user)
    return nil unless user
    patch_ratings.find_by(user_id: user.id)
  end

  def self.recount_all_ratings!
    recounted = 0
    find_each do |patch|
      patch.recount_ratings!
      recounted += 1
    end
    recounted
  end

  def recount_ratings!
    useful = patch_ratings.where(is_useful: true).count
    not_useful = patch_ratings.where(is_useful: false).count
    update_columns(useful_count: useful, not_useful_count: not_useful)
  end

  def self.random_unrated_for(user, base_scope: nil)
    scope = base_scope || active.unresolved
    scope = scope.where.not(id: PatchRating.select(:patch_id).where(user_id: user.id)) if user

    # Use offset-based random selection for better performance on large tables
    count = scope.count
    return nil if count.zero?
    scope.offset(rand(count)).first
  end

  def self.import_from_directory(path)
    imported = 0
    errors = []

    Dir
      .glob(File.join(path, "*.md"))
      .each do |md_file|
        commit_hash = File.basename(md_file, ".md")
        patch_file = File.join(path, "#{commit_hash}.patch")

        next unless File.exist?(patch_file)

        begin
          markdown_content = File.read(md_file)
          diff_content = File.read(patch_file)

          parsed = parse_markdown(markdown_content)

          patch = Patch.find_or_initialize_by(commit_hash: commit_hash)
          patch.assign_attributes(
            title: parsed[:title],
            summary: parsed[:summary],
            markdown_content: markdown_content,
            diff_content: diff_content,
            issue_type: parsed[:issue_type],
            audit_date: parsed[:audit_date],
            repository: parsed[:repository],
          )
          patch.save!
          imported += 1
        rescue StandardError => e
          errors << { file: md_file, error: e.message }
        end
      end

    { imported: imported, errors: errors }
  end

  def self.parse_markdown(content)
    result = {}

    # Title: First # line (not ##, just single #)
    if match = content.match(/^# ([^\n]+)/)
      result[:title] = match[1].strip
    end

    # Audit date: **Audited:** YYYY-MM-DD
    if match = content.match(/\*\*Audited:\*\*\s*(\d{4}-\d{2}-\d{2})/)
      result[:audit_date] = Date.parse(match[1])
    end

    # Repository: **Repository:** ...
    if match = content.match(/\*\*Repository:\*\*\s*(.+)$/)
      result[:repository] = match[1].strip
    end

    # Issue type: [bug], [security], etc. in the content
    if content.match(/\[security\]/i)
      result[:issue_type] = "security"
    elsif content.match(/\[bug\]/i)
      result[:issue_type] = "bug"
    elsif content.match(/\[enhancement\]/i)
      result[:issue_type] = "enhancement"
    elsif content.match(/\[feature\]/i)
      result[:issue_type] = "feature"
    end

    # Summary: Content under ## Summary
    if match = content.match(/## Summary\s*\n+(.*?)(?=\n## |\z)/m)
      result[:summary] = match[1].strip
    end

    result
  end
end
