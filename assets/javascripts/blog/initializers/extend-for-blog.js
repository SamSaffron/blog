import { withPluginApi } from "discourse/lib/plugin-api";
import { cookAsync } from "discourse/lib/text";

export default {
  name: "extend-for-blog",

  initialize() {
    //const siteSettings = container.lookup("site-settings:main");
    //
    withPluginApi("0.13.0", (api) => {
      api.modifyClass("controller:topic", {
        onFastEditMessage: function (data) {
          const post = this.model.postStream.findLoadedPost(data.post_id);
          if (post) {
            cookAsync(data.raw).then((cooked) => {
              post.set("raw", data.raw);
              post.set("cooked", cooked);

              // trigger events forces HTTP calls, so I am sledghammering this
              // this.appEvents.trigger("post-stream:refresh", { id: data.post_id });
              document.querySelector(
                `#post_${data.post_number} .cooked`
              ).innerHTML = cooked;
            });
          }
        },
        subscribe: function () {
          this._super();

          if (
            this.model.isPrivateMessage &&
            this.model.details.allowed_users &&
            this.model.details.allowed_users.filter((u) => u.id === -101)
              .length === 1
          ) {
            this.messageBus.subscribe(
              "/fast-edit/" + this.model.id,
              this.onFastEditMessage.bind(this)
            );
          }
        },
        unsubscribe: function () {
          this.messageBus.unsubscribe("/fast-edit/*");
          this._super();
        },
      });
    });
  },
};
