import { withPluginApi } from "discourse/lib/plugin-api";
import BlogShareTokenModal from "../components/modal/blog-share-token";

export default {
  name: "blog-topic-actions",
  initialize(owner) {
    withPluginApi((api) => {
      // Add share link button to admin topic menu (wrench icon)
      api.addTopicAdminMenuButton((topic) => {
        return {
          action: () => {
            const modal = owner.lookup("service:modal");
            modal.show(BlogShareTokenModal, {
              model: {
                topicId: topic.id,
                currentUser: api.getCurrentUser(),
              },
            });
          },
          icon: "link",
          className: "topic-share-token",
          label: "blog.topic_actions.share",
        };
      });
    });
  },
};
