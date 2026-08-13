// In the SwiftPM build the app logic lives in the MoreCornersCore library, so
// the executable imports it. The hand-written Xcode project compiles every
// source into one target instead, where MoreCornersApp is already in scope and
// there is no module to import — `canImport` picks the right path per build.
#if canImport(MoreCornersCore)
import MoreCornersCore
#endif

MoreCornersApp.run()
