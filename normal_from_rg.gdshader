shader_type canvas_item;
// Rebuilds the normal from its RG channels.

/** Normal map storing only the X and Y axes in the RG channels. */
uniform sampler2D normal_rg;

void fragment() {
	vec2 normal_xy = texture(normal_rg, UV).rg * 2.0 - 1.0;
	float normal_z = sqrt(max(0.0, 1.0 - dot(normal_xy, normal_xy)));
	NORMAL = vec3(normal_xy, normal_z);
}
