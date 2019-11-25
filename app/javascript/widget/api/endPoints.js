const sendMessage = content => ({
  url: `/api/v1/widget/messages${window.location.search}`,
  params: {
    message: {
      content,
      timestamp: new Date().toString(),
      referer_url: window.parentUrl ? window.parentUrl : '',
    },
  },
});

const getConversation = () => ({
  url: `/api/v1/widget/messages${window.location.search}`,
});

export default {
  sendMessage,
  getConversation,
};
