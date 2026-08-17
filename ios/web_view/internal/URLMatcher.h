#ifndef IOS_WEB_VIEW_INTERNAL_URL_MATCHER_H_
#define IOS_WEB_VIEW_INTERNAL_URL_MATCHER_H_

#include <string>
namespace url { class GURL; }

namespace web_view {

class URLMatcher {
 public:
  URLMatcher() {}
  explicit URLMatcher(const std::string& pattern) {}
  bool Matches(const url::GURL& /*url*/) const { return true; }
};

}  // namespace web_view

#endif  // IOS_WEB_VIEW_INTERNAL_URL_MATCHER_H_
