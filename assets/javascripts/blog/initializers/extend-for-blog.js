import { withPluginApi } from "discourse/lib/plugin-api";
import { cookAsync } from "discourse/lib/text";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import loadScript from "discourse/lib/load-script";

export default {
  name: "extend-for-blog",

  initialize() {
    //const siteSettings = container.lookup("site-settings:main");
    //
    withPluginApi("0.13.0", (api) => {
      api.addPostMenuButton("cancel-gpt", (post) => {
        if (post.user.id === -102) {
          return {
            icon: "pause",
            action: "cancelGpt",
            title: "blog.stop_generating",
            className: "btn btn-default stop-generating",
            position: "first",
          };
        }
      });

      api.attachWidgetAction("post", "cancelGpt", function () {
        ajax("/blog/gpt/cancel/" + this.model.id, { type: "POST" }).catch(
          popupAjaxError
        );
      });

      api.modifyClass("controller:topic", {
        onFastEditMessage: function (data) {
          const post = this.model.postStream.findLoadedPost(data.post_id);
          if (post && data.raw) {
            cookAsync(data.raw).then((cooked) => {
              post.set("raw", data.raw);
              post.set("cooked", cooked);

              document
                .querySelector(`#post_${data.post_number}`)
                .classList.add("generating");

              // trigger events forces HTTP calls, so I am sledghammering this
              // this.appEvents.trigger("post-stream:refresh", { id: data.post_id });
              // document.querySelector(
              //   `#post_${data.post_number} .cooked`
              // ).innerHTML = cooked;

              const cookedElement = document.createElement("div");
              cookedElement.innerHTML = cooked;

              let element = document.querySelector(
                `#post_${data.post_number} .cooked`
              );

              loadScript("/javascripts/diffhtml.min.js").then(() => {
                window.diff.innerHTML(element, cookedElement.innerHTML);
              });
            });
          }
          if (post && data.done) {
            document
              .querySelector(`#post_${data.post_number}`)
              .classList.remove("generating");
          }
        },
        subscribe: function () {
          this._super();

          if (
            this.model.isPrivateMessage &&
            this.model.details.allowed_users &&
            this.model.details.allowed_users.filter((u) => u.id === -102)
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
