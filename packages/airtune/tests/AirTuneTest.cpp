#include <algorithm>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iterator>
#include <map>
#include <string>
#include <vector>

#include "CrossStoreRuntime.h"

class RadioHost : public crossstore::Host {
 public:
  crossstore::Canvas scene;
  std::map<std::string, std::string> files;
  std::vector<std::string> calls;
  std::string state = "idle", error = "none", url, prompt, initial;
  int width = 432, height = 640, volume = 25;
  unsigned now = 0, frames = 0, writes = 0, revision = 0;
  bool zh = false, permission = true, hardware = true, failWrite = false, exited = false;
  void title(const char*) override {}
  void clear() override {
    scene.clear();
    ++frames;
  }
  void grid(unsigned) override {}
  void caption(const char*) override {}
  bool row(const char*, const char*) override { return true; }
  bool capability(const char*) const override { return hardware; }
  bool chinese() const override { return zh; }
  bool allowed(const char*) const override { return permission; }
  uint32_t milliseconds() const override { return now; }
  bool read(const char* key, char* out, size_t size) override {
    const auto found = files.find(key);
    if (found == files.end() || found->second.size() >= size) return false;
    std::memcpy(out, found->second.c_str(), found->second.size() + 1);
    return true;
  }
  bool write(const char* key, const char* value, size_t bytes) override {
    ++writes;
    assert(bytes <= 2048);
    if (failWrite) return false;
    files[key].assign(value, bytes);
    return true;
  }
  void input(const char* title, const char* value) override {
    prompt = title;
    initial = value;
  }
  void notify(const char*) override {}
  bool open(const char*) override { return false; }
  void exit() override { exited = true; }
  void size(int& w, int& h) const override {
    w = width;
    h = height;
  }
  bool canvas() override { return true; }
  bool draw(const crossstore::DrawCommand& c, const char* label) override {
    assert(c.x >= 0 && c.y >= 0 && c.x + c.width <= width && c.y + c.height <= height);
    if (c.kind == crossstore::DrawKind::Button || c.kind == crossstore::DrawKind::Hit) {
      if (c.width < 44 || c.height < 44) {
        std::fprintf(stderr, "small control %d at %d x %d: %d x %d\n", c.action, width, height, c.width, c.height);
        std::abort();
      }
      for (size_t i = 0; i < scene.controlCount; ++i) {
        const auto& other = scene.commands[scene.controls[i]];
        const int dx = std::max<int>(c.x - other.x - other.width, other.x - c.x - c.width);
        const int dy = std::max<int>(c.y - other.y - other.height, other.y - c.y - c.height);
        assert(dx >= 6 || dy >= 6);
      }
    }
    return scene.add(c, label);
  }
  bool system(const char* command, const char* argument, int64_t value, crossstore::ServiceReply& reply) override {
    calls.emplace_back(command);
    bool ok = true;
    if (!std::strcmp(command, "radio.start"))
      ok = permission && hardware;
    else if (!std::strcmp(command, "radio.play")) {
      if (permission && hardware) {
        url = argument;
        state = "connecting";
        error = "none";
        ++revision;
      } else
        ok = false;
    } else if (!std::strcmp(command, "radio.stop")) {
      state = "idle";
      error = "none";
      ++revision;
    } else if (!std::strcmp(command, "radio.volume")) {
      volume = static_cast<int>(value);
      ++revision;
    } else
      assert(!std::strcmp(command, "radio.status"));
    std::snprintf(reply.text, sizeof(reply.text), "%s", state.c_str());
    reply.a = volume;
    reply.b = 1024;
    reply.c = revision;
    std::snprintf(reply.extra, sizeof(reply.extra), "%s", ok ? error.c_str() : "permission");
    return ok;
  }
  bool hasText(const char* needle) const {
    for (size_t i = 0; i < scene.count; ++i)
      if (std::strstr(scene.text + scene.commands[i].text, needle)) return true;
    return false;
  }
  bool hasControl(int id) const {
    for (size_t i = 0; i < scene.controlCount; ++i)
      if (scene.commands[scene.controls[i]].action == id) return true;
    return false;
  }
  void dump(const char* name) const {
    const char* directory = std::getenv("AIRTUNE_PREVIEW_DIR");
    if (!directory || !zh || width < 400 || height < 320) return;
    std::ofstream out(std::string(directory) + "/" + std::to_string(width) + "x" + std::to_string(height) + "-" + name +
                      ".json");
    out << "{\"width\":" << width << ",\"height\":" << height << ",\"commands\":[";
    for (size_t i = 0; i < scene.count; ++i) {
      const auto& c = scene.commands[i];
      if (i) out << ',';
      out << "{\"kind\":" << int(c.kind) << ",\"x\":" << c.x << ",\"y\":" << c.y << ",\"w\":" << c.width
          << ",\"h\":" << c.height << ",\"gray\":" << int(c.gray) << ",\"radius\":" << int(c.radius)
          << ",\"font\":" << int(c.font) << ",\"align\":" << int(c.align) << ",\"style\":" << int(c.style)
          << ",\"text\":" << std::quoted(scene.text + c.text) << '}';
    }
    out << "]}";
  }
  unsigned count(const char* command) const { return std::count(calls.begin(), calls.end(), command); }
};

static size_t peak = 0;
static void event(crossstore::Runtime& vm, const char* name, int id = 0, const char* text = "") {
  if (!vm.event(name, id, text)) {
    std::fprintf(stderr, "%s(%d): %s\n", name, id, vm.error());
    std::abort();
  }
  peak = std::max(peak, vm.peak());
}
static void select(crossstore::Runtime& vm, int id) { event(vm, "on_select", id); }
static void load(crossstore::Runtime& vm, const std::string& script) {
  if (!vm.load(script.data(), script.size(), 131072)) {
    std::fprintf(stderr, "load: %s (peak=%zu)\n", vm.error(), vm.peak());
    std::abort();
  }
  peak = std::max(peak, vm.peak());
}
static void custom(crossstore::Runtime& vm, const char* name, const char* url) {
  select(vm, 3);
  select(vm, 30);
  select(vm, 31);
  event(vm, "on_input", 0, name);
  select(vm, 32);
  event(vm, "on_input", 0, url);
  select(vm, 33);
}

int main(int argc, char** argv) {
  assert(argc == 2);
  std::ifstream in(argv[1]);
  const std::string script{std::istreambuf_iterator<char>(in), {}};
  assert(!script.empty() && script.size() <= crossstore::MAX_SCRIPT_BYTES);
  for (const auto size :
       {std::pair{432, 640}, std::pair{640, 360}, std::pair{240, 320}, std::pair{640, 280}, std::pair{960, 400}}) {
    for (bool zh : {false, true}) {
      RadioHost h;
      h.width = size.first;
      h.height = size.second;
      h.zh = zh;
      crossstore::Runtime vm(h);
      load(vm, script);
      assert(h.count("radio.start") == 1 && h.count("radio.play") == 0 && h.writes == 0 && h.volume == 50);
      h.dump("playing");
      unsigned frames = h.frames;
      for (int i = 0; i < 8; ++i) {
        h.now += 1000;
        event(vm, "on_tick");
      }
      assert(h.frames == frames && h.writes == 0);  // Idle ticks never redraw/save.
      select(vm, 2);
      h.dump("stations");
      select(vm, 101);
      assert(h.state == "connecting" && !h.url.empty());
      const std::string first = h.url;
      h.state = "playing";
      h.now += 1000;
      event(vm, "on_tick");
      frames = h.frames;
      ++h.revision;
      h.now += 1000;
      event(vm, "on_tick");
      assert(h.frames == frames);  // Transport counters/revision alone do not repaint e-ink.
      select(vm, 11);
      assert(!h.files["favorite_01"].empty());
      select(vm, 2);
      if (h.hasControl(102))
        select(vm, 102);
      else {
        select(vm, 21);
        select(vm, 101);
      }
      assert(h.url != first && h.count("radio.play") == 2);
      select(vm, 10);
      assert(h.state == "idle");
      select(vm, 10);
      assert(h.state == "connecting");
      select(vm, 13);
      assert(h.volume == 60 && h.files["volume"] == "60");
      select(vm, 12);
      assert(h.volume == 50 && h.files["volume"] == "50");
      h.failWrite = true;
      const auto volumeCalls = h.count("radio.volume");
      select(vm, 13);
      assert(h.volume == 50 && h.count("radio.volume") == volumeCalls && h.files["volume"] == "50");
      h.failWrite = true;
      const auto plays = h.count("radio.play");
      select(vm, 2);
      select(vm, 101);
      assert(h.count("radio.play") == plays);
      assert(h.hasText(zh ? "保存失败" : "Save failed"));
      h.failWrite = false;
      select(vm, 3);
      select(vm, 30);
      select(vm, 31);
      // Firmware emits no on_input on keyboard cancellation. A later URL
      // response must not populate the name or accidentally save a favorite.
      const auto writes = h.writes;
      select(vm, 32);
      event(vm, "on_input", 0, "http://example.test/live.mp3");
      select(vm, 33);
      assert(h.writes == writes && h.hasText(zh ? "请填写" : "Enter a name"));
      select(vm, 31);
      event(vm, "on_input", 0, "My radio");
      h.failWrite = true;
      select(vm, 33);
      assert(h.files["favorite_02"].empty());
      h.failWrite = false;
      select(vm, 33);
      assert(h.files["favorite_02"] == "My radio\nhttp://example.test/live.mp3");
      select(vm, 201);
      h.failWrite = true;
      select(vm, 41);
      assert(!h.files["favorite_01"].empty());
      h.failWrite = false;
      select(vm, 41);
      assert(h.files["favorite_01"].empty());
      select(vm, 30);
      select(vm, 32);
      event(vm, "on_input", 0, "https://example.test/radio.m3u8");
      assert(h.hasText(zh ? "直链" : "direct"));
      select(vm, 34);
      event(vm, "on_resize");
      select(vm, 1);
      event(vm, "on_network", 0);
      assert(h.hasText(zh ? "连接已取消" : "Connection cancelled"));
      event(vm, "on_back");
      assert(h.exited && h.state == "idle");
      event(vm, "on_stop");
      assert(vm.peak() < 131072);
    }
  }
  {
    RadioHost h;
    h.permission = false;
    crossstore::Runtime vm(h);
    load(vm, script);
    assert(h.count("radio.play") == 0 && h.hasText("Store settings"));
    select(vm, 10);
    assert(h.count("radio.play") == 0 && h.writes == 0);
    h.permission = true;
    select(vm, 10);
    assert(h.count("radio.play") == 1);
  }
  for (int saved : {0, 25, 37, 100}) {
    for (bool allowedAtStart : {false, true}) {
      RadioHost h;
      h.files["volume"] = std::to_string(saved);
      h.permission = allowedAtStart;
      crossstore::Runtime vm(h);
      load(vm, script);
      assert(h.files["volume"] == std::to_string(saved) && h.writes == 0);
      if (!allowedAtStart) {
        h.permission = true;
        select(vm, 10);
      }
      assert(h.volume == saved);  // Keep mute and older non-ten-step settings.
      select(vm, 13);
      assert(h.volume == std::min(100, saved + 10));
      for (int i = 0; i < 11; ++i) select(vm, 12);
      assert(h.volume == 0);
      for (int i = 0; i < 11; ++i) select(vm, 13);
      assert(h.volume == 100);
      event(vm, "on_stop");
    }
  }
  {
    RadioHost h;
    h.hardware = false;
    crossstore::Runtime vm(h);
    load(vm, script);
    assert(h.hasText("does not support") && h.count("radio.start") == 0);
  }
  {
    RadioHost h;
    const std::string longUrl = "http://x/" + std::string(502, 'a');
    h.files["last_station"] = "Long URL\n" + longUrl;
    h.files["favorite_01"] = "broken record";
    h.files["volume"] = "10000";
    crossstore::Runtime vm(h);
    load(vm, script);
    assert(h.volume == 50);
    select(vm, 10);
    assert(h.url == longUrl && h.url.size() == 511);
    h.state = "error";
    h.error = "unsupported";
    event(vm, "on_service");
    assert(h.hasText("direct MP3"));
    event(vm, "on_stop");
    assert(h.state == "idle");
  }
  {
    RadioHost h;
    crossstore::Runtime vm(h);
    load(vm, script);
    for (int i = 0; i < 12; ++i)
      custom(vm, ("Station " + std::to_string(i)).c_str(),
             ("http://example.test/" + std::to_string(i) + ".mp3").c_str());
    const unsigned writes = h.writes;
    custom(vm, "Extra", "http://example.test/extra.mp3");
    assert(h.writes == writes && h.hasText("12 favorites"));
    event(vm, "on_stop");
    vm.close();
    load(vm, script);
    select(vm, 3);
    assert(h.hasText("12/12") && h.count("radio.play") == 0);
  }
  std::printf(
      "AirTune: real runtime, bilingual five-size layout, persistence/cancel/permissions, bounded favorites, "
      "station/volume/lifecycle passed; peak VM %zu bytes\n",
      peak);
}
