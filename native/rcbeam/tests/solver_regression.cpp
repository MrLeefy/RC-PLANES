#include "rcbeam/solver.hpp"
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <new>

static std::size_t allocations = 0;
void* operator new(std::size_t n) {
    ++allocations;
    if (void* p = std::malloc(n)) return p;
    throw std::bad_alloc();
}
void operator delete(void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
#define CHECK(x) do { if (!(x)) { std::cerr << "FAIL line " << __LINE__ << ": " #x "\n"; return 1; } } while (0)

int main() {
    using namespace rcbeam;
    for (unsigned substeps : {4u, 8u}) {
        SolverConfig cfg;
        cfg.normal_substeps = substeps;
        cfg.impact_substeps = substeps;
        cfg.global_velocity_damping = 0;
        Solver s(cfg);
        s.reserve(3, 0);
        s.add_node({}, 1, true);
        s.add_node({0.1f, 0, 0}, 2);
        s.add_node({0.2f, 0, 0}, 3);
        s.apply_radial_impulse({}, {1, 0, 0}, 1);
        CHECK(std::abs(s.nodes()[1].velocity.x * 2 + s.nodes()[2].velocity.x * 3 - 1) < 1e-6f);
        const float before = s.nodes()[1].velocity.x;
        s.apply_force(1, {240, 0, 0});
        s.step(1.0f / 120, {});
        CHECK(std::abs(s.nodes()[1].velocity.x - before - 1) < 1e-5f);
        const float after = s.nodes()[1].velocity.x;
        s.step(1.0f / 120, {});
        CHECK(s.nodes()[1].velocity.x == after);
        CHECK(s.step(1, {}).substeps == 0);
    }
    SolverConfig cfg;
    cfg.normal_substeps = 10000;
    cfg.impact_substeps = 20000;
    cfg.max_substeps = 4;
    Solver bounded(cfg);
    bounded.add_node({}, 1);
    bounded.notify_impact(1);
    CHECK(bounded.step(1.0f / 120, {}).substeps == 4);

    Solver plastic;
    plastic.reserve(2, 1);
    plastic.add_node({}, 1, true);
    plastic.add_node({1, 0, 0}, 1);
    Material m;
    m.stiffness_n_per_m = 0;
    m.damping_ns_per_m = 0;
    m.yield_tension = 0.01f;
    m.break_tension = 1;
    m.plasticity_rate = 20;
    plastic.add_beam(0, 1, m);
    plastic.apply_impulse(1, {1, 0, 0});
    for (int i = 0; i < 30; ++i) plastic.step(1.0f / 120, {});
    CHECK(plastic.beams()[0].rest_length > 1.01f);
    CHECK(!plastic.beams()[0].broken);
    CHECK(plastic.beams()[0].rest_length <= 1.25f);

    // More than 64 independent groups used to grow the hot-path group buffer.
    Solver fracture;
    fracture.reserve(141, 140);
    fracture.add_node({}, 1, true);
    m.break_tension = 0.001f;
    m.break_compression = 0.001f;
    for (unsigned i = 1; i <= 140; ++i) {
        fracture.add_node({1, 0, 0}, 1);
        fracture.add_beam(0, i, m, static_cast<std::uint16_t>((i + 1) / 2));
        fracture.apply_impulse(i, {10, 0, 0});
    }
    const auto before = allocations;
    for (int i = 0; i < 120; ++i) {
        fracture.step(1.0f / 120, {});
        for (auto event : fracture.break_events()) CHECK(fracture.beams()[event].broken);
        fracture.clear_break_events();
    }
    CHECK(allocations == before);
    for (const Beam& beam : fracture.beams()) CHECK(beam.broken);
    std::cout << "RCBeam regression PASS: force duration, impulse conservation, hard cap, plasticity, fracture, zero step/event allocations\n";
}
