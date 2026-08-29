// Screenshot helper for the bedroom panel simulator (bedroom-panel-sim.yaml).
//
// `./sim.sh shot` needs the SDL renderer the `sdl` display component draws
// with, so it can read the backbuffer straight out of the process. The
// component keeps that pointer protected and the class is final, so the
// usual "derive and expose" route is closed; this uses the explicit
// template instantiation loophole instead (access checks are skipped for
// explicit instantiations — see [temp.explicit]/12), which is legal C++ and
// costs nothing at runtime. Host-only: the real panel never compiles this.
#pragma once
#ifdef USE_HOST
#include "esphome/components/sdl/sdl_esphome.h"

namespace sim_shot {

template<typename Tag, typename Tag::type M> struct Rob {
  friend typename Tag::type get(Tag) { return M; }
};
struct RendererTag {
  typedef SDL_Renderer *esphome::sdl::Sdl::*type;
  friend type get(RendererTag);
};
template struct Rob<RendererTag, &esphome::sdl::Sdl::renderer_>;

inline SDL_Renderer *renderer_of(esphome::sdl::Sdl *display) { return display->*get(RendererTag()); }

// Writes the renderer's current backbuffer (the last presented frame — the
// component uses SDL_RENDERER_SOFTWARE, whose buffer persists between
// presents) to `path` as a 24-bit BMP. Returns true on success; on failure
// SDL_GetError() says why.
inline bool save_frame(esphome::sdl::Sdl *display, const char *path) {
  SDL_Renderer *ren = renderer_of(display);
  if (ren == nullptr) {
    SDL_SetError("display has no SDL renderer (window creation failed?)");
    return false;
  }
  int w = 0, h = 0;
  if (SDL_GetRendererOutputSize(ren, &w, &h) != 0 || w <= 0 || h <= 0)
    return false;
  SDL_Surface *surf = SDL_CreateRGBSurfaceWithFormat(0, w, h, 24, SDL_PIXELFORMAT_RGB24);
  if (surf == nullptr)
    return false;
  bool ok = SDL_RenderReadPixels(ren, nullptr, SDL_PIXELFORMAT_RGB24, surf->pixels, surf->pitch) == 0 &&
            SDL_SaveBMP(surf, path) == 0;
  SDL_FreeSurface(surf);
  return ok;
}

}  // namespace sim_shot
#endif
