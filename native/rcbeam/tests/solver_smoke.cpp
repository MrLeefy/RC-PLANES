#include "rcbeam/solver.hpp"

#include <cassert>
#include <cmath>
#include <iostream>

namespace {

bool finite_vec(const rcbeam::Vec3& v) {
    return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);
}

} // namespace

int main() {
    using namespace rcbeam;

    SolverConfig config{};
    config.normal_substeps = 4;
    config.impact_substeps = 8;
    config.max_substeps = 8;

    Solver solver(config);
    solver.reserve(8, 16);

    const auto root = solver.add_node({0.0f, 0.0f, 0.0f}, 0.5f, true);
    const auto tip = solver.add_node({1.0f, 0.0f, 0.0f}, 0.25f, false);

    Material elastic = material_preset(MaterialKind::Aluminum);
    elastic.break_tension = 0.50f;
    elastic.break_compression = 0.50f;

    const auto beam = solver.add_beam(root, tip, elastic);
    (void)beam;

    solver.apply_impulse(tip, {0.0f, 0.6f, 0.0f});
    solver.notify_impact(0.8f);

    for (int i = 0; i < 120; ++i) {
        const StepStats stats = solver.step(1.0f / 120.0f, {0.0f, 0.0f, 0.0f});
        assert(stats.substeps >= 4);
        for (const Node& node : solver.nodes()) {
            assert(finite_vec(node.position));
            assert(finite_vec(node.velocity));
        }
    }

    // Deliberately brittle attachment group.
    Solver break_test(config);
    break_test.reserve(4, 4);
    const auto a = break_test.add_node({0.0f, 0.0f, 0.0f}, 0.4f, true);
    const auto b = break_test.add_node({1.0f, 0.0f, 0.0f}, 0.2f, false);
    const auto c = break_test.add_node({2.0f, 0.0f, 0.0f}, 0.2f, false);

    Material brittle = material_preset(MaterialKind::CarbonFiber);
    brittle.break_tension = 0.025f;
    brittle.break_compression = 0.025f;

    break_test.add_beam(a, b, brittle, 7);
    break_test.add_beam(b, c, brittle, 7);
    break_test.apply_impulse(c, {8.0f, 0.0f, 0.0f});
    break_test.notify_impact(1.0f);

    bool broke = false;
    for (int i = 0; i < 16 && !broke; ++i) {
        break_test.step(1.0f / 120.0f, {0.0f, 0.0f, 0.0f});
        const auto events = break_test.consume_break_events();
        broke = !events.empty();
    }

    assert(broke);
    assert(break_test.beams()[0].broken);
    assert(break_test.beams()[1].broken);

    std::cout << "RCBeam smoke test passed\n";
    return 0;
}
