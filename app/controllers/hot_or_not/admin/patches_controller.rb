# frozen_string_literal: true

module HotOrNot
  module Admin
    class PatchesController < ApplicationController
      requires_login
      before_action :ensure_admin
      skip_before_action :check_xhr

      layout "hot_or_not"

      def index
        @page = (params[:page] || 1).to_i
        @per_page = 50
        @total_patches = Patch.count
        @active_patches = Patch.active.count
        @patches = Patch.order(created_at: :desc).offset((@page - 1) * @per_page).limit(@per_page)
        @total_pages = (@total_patches.to_f / @per_page).ceil
        @total_ratings = PatchRating.count
        @total_hot = PatchRating.where(is_hot: true).count
      end

      def show
        @patch = Patch.find(params[:id])
      end

      def new
        @patch = Patch.new
      end

      def create
        @patch = Patch.new(patch_params)
        if @patch.save
          redirect_to "/hot-or-not/admin/patches", notice: "Patch created successfully"
        else
          render :new
        end
      end

      def edit
        @patch = Patch.find(params[:id])
      end

      def update
        @patch = Patch.find(params[:id])
        if @patch.update(patch_params)
          redirect_to "/hot-or-not/admin/patches", notice: "Patch updated successfully"
        else
          render :edit
        end
      end

      def destroy
        @patch = Patch.find(params[:id])
        @patch.destroy
        redirect_to "/hot-or-not/admin/patches", notice: "Patch deleted"
      end

      def toggle_active
        @patch = Patch.find(params[:id])
        if @patch.update(active: !@patch.active)
          redirect_to "/hot-or-not/admin/patches", notice: "Patch #{@patch.active ? 'activated' : 'deactivated'}"
        else
          redirect_to "/hot-or-not/admin/patches", alert: "Failed to update patch: #{@patch.errors.full_messages.join(', ')}"
        end
      end

      def recount_all
        count = Patch.recount_all_ratings!
        redirect_to "/hot-or-not/admin/patches", notice: "Recounted ratings for #{count} patches"
      end

      def import
      end

      def perform_import
        if params[:files].blank?
          redirect_to "/hot-or-not/admin/patches/import", alert: "No files provided"
          return
        end

        @result = import_from_uploaded_files(params[:files])
        render :import_results
      end

      MAX_FILE_SIZE = 1.megabyte
      COMMIT_HASH_PATTERN = /\A[0-9a-f]{7,40}\z/i

      def import_from_uploaded_files(files)
        result = {
          total_files: 0,
          md_files: 0,
          patch_files: 0,
          created: 0,
          updated: 0,
          skipped: [],
          errors: [],
        }

        # Group files by commit hash (filename without extension)
        file_groups = {}
        files.each do |file|
          next unless file.respond_to?(:original_filename)
          result[:total_files] += 1

          # Check file size
          if file.size > MAX_FILE_SIZE
            result[:skipped] << {
              commit_hash: File.basename(file.original_filename, ".*"),
              reason: "File too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)",
            }
            next
          end

          basename = File.basename(file.original_filename, ".*")
          ext = File.extname(file.original_filename).downcase

          if ext == ".md"
            result[:md_files] += 1
          elsif ext == ".patch"
            result[:patch_files] += 1
          else
            next
          end

          file_groups[basename] ||= {}
          file_groups[basename][ext] = file
        end

        file_groups.each do |raw_commit_hash, group|
          # Normalize commit hash for consistent lookup
          commit_hash = raw_commit_hash.downcase.strip

          # Validate commit hash format
          unless commit_hash.match?(COMMIT_HASH_PATTERN)
            result[:skipped] << { commit_hash: raw_commit_hash, reason: "Invalid commit hash format" }
            next
          end

          unless group[".md"] && group[".patch"]
            missing = group[".md"] ? ".patch" : ".md"
            result[:skipped] << { commit_hash: commit_hash, reason: "Missing #{missing} file" }
            next
          end

          begin
            markdown_content = group[".md"].read
            diff_content = group[".patch"].read

            parsed = Patch.parse_markdown(markdown_content)

            patch = Patch.find_or_initialize_by(commit_hash: commit_hash)
            is_new = patch.new_record?

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

            if is_new
              result[:created] += 1
            else
              result[:updated] += 1
            end
          rescue StandardError => e
            Rails.logger.error("Patch import error for #{commit_hash}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
            result[:errors] << { commit_hash: commit_hash, error: e.message }
          end
        end

        result
      end

      private

      def ensure_admin
        raise Discourse::InvalidAccess unless current_user&.admin?
      end

      def patch_params
        params.require(:patch).permit(
          :commit_hash,
          :title,
          :summary,
          :markdown_content,
          :diff_content,
          :issue_type,
          :audit_date,
          :repository,
          :active
        )
      end
    end
  end
end
