import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

export default class BlogShareTokenModal extends Component {
  @service dialog;

  @tracked tokens = [];
  @tracked isLoading = false;
  @tracked isCreating = false;

  constructor() {
    super(...arguments);
    this.loadTokens();
  }

  async loadTokens() {
    this.isLoading = true;
    try {
      this.tokens = await ajax(
        `/topics/${this.args.model.topicId}/topic_share_tokens`
      );
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async createToken() {
    this.isCreating = true;
    try {
      const response = await ajax(
        `/topics/${this.args.model.topicId}/topic_share_tokens`,
        {
          type: "POST",
        }
      );

      this.tokens = [
        {
          id: Date.now(), // Temporary ID
          token: response.token,
          expires_at: response.expires_at,
          share_url: response.share_url,
          user: this.args.model.currentUser,
        },
        ...this.tokens,
      ];
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isCreating = false;
    }
  }

  @action
  async deleteToken(token) {
    try {
      await ajax(
        `/topics/${this.args.model.topicId}/topic_share_tokens/${token.id}`,
        {
          type: "DELETE",
        }
      );
      this.tokens = this.tokens.filter((t) => t.id !== token.id);
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
      this.dialog.alert(i18n("blog.share_tokens.copied"));
    });
  }

  get hasTokens() {
    return this.tokens.length > 0;
  }

  <template>
    <DModal
      @title={{i18n "blog.share_tokens.title"}}
      @closeModal={{@closeModal}}
      class="blog-share-token-modal"
    >
      <:body>
        {{#if this.isLoading}}
          <div class="loading-container">
            {{i18n "loading"}}
          </div>
        {{else}}
          <div class="tokens-list">
            {{#if this.hasTokens}}
              {{#each this.tokens as |token|}}
                <div class="token-item">
                  <div class="token-info">
                    <div class="token-url">
                      <input
                        type="text"
                        value={{token.share_url}}
                        readonly
                        class="token-input"
                      />
                      <DButton
                        @action={{fn this.copyToClipboard token.share_url}}
                        @label="blog.share_tokens.copy"
                        class="btn-primary copy-btn"
                      />
                    </div>
                    <div class="token-meta">
                      <span class="expires-at">
                        {{i18n "blog.share_tokens.expires"}}
                        {{token.expires_at}}
                      </span>
                      <DButton
                        @action={{fn this.deleteToken token}}
                        @label="blog.share_tokens.delete"
                        class="btn-danger delete-btn"
                      />
                    </div>
                  </div>
                </div>
              {{/each}}
            {{else}}
              <div class="no-tokens">
                <p>{{i18n "blog.share_tokens.no_tokens"}}</p>
              </div>
            {{/if}}
          </div>

          <div class="create-token-section">
            <DButton
              @action={{this.createToken}}
              @label={{if
                this.isCreating
                "blog.share_tokens.creating"
                "blog.share_tokens.create_new"
              }}
              @disabled={{this.isCreating}}
              class="btn-primary create-token-btn"
            />
          </div>
        {{/if}}
      </:body>
    </DModal>
  </template>
}
