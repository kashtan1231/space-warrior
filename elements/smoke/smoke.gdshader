shader_type canvas_item;
render_mode unshaded;

// Раскрашивает дым. Узел Smoke — это CanvasGroup: все клубы сначала складываются в его
// отдельный буфер как плотность (см. smoke_puff.gdshader), и только потом этот шейдер один
// раз проходит по сумме. Поэтому соседние клубы сливаются в одно облако с общим контуром,
// а на экран попадают только цвета палитры, без полупрозрачных полутонов между ними.

// Сумма клубов, нарисованная дочерними узлами группы.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

/** Размер пикселя дыма в пикселях игрового экрана. 2 — как у корабля игрока, нарисованного с масштабом 2. Больше — дым крупнее и грубее. */
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;
/** Размер видимой области игры в пикселях. Выставляет smoke.gd при запуске и при смене размера окна — руками не менять. */
uniform vec2 canvas_size = vec2(1280.0, 720.0);

group_uniforms density;
/** Плотность, с которой дым становится видимым. Меньше — шлейф шире и дольше виден, пока рассеивается; больше — остаются только густые сердцевины. */
uniform float thin_threshold : hint_range(0.0, 1.0, 0.01) = 0.08;
/** С какой плотности дым рисуется средним цветом. */
uniform float mid_threshold : hint_range(0.0, 1.0, 0.01) = 0.22;
/** С какой плотности дым рисуется самым светлым цветом сердцевины. */
uniform float dense_threshold : hint_range(0.0, 1.0, 0.01) = 0.45;
/** Размах дизеринга на границах цветов, в единицах плотности. 0 — резкие ступени; больше — переход рассыпается шахматкой пикселей. */
uniform float dither : hint_range(0.0, 0.3, 0.01) = 0.05;

group_uniforms colors;
/** Цвет редкого дыма на краях облака. */
uniform vec4 thin_color : source_color = vec4(0.4118, 0.3098, 0.3843, 1.0);
/** Цвет дыма средней плотности. */
uniform vec4 mid_color : source_color = vec4(0.4980, 0.4392, 0.5412, 1.0);
/** Цвет густой сердцевины облака. */
uniform vec4 dense_color : source_color = vec4(0.6078, 0.6706, 0.6980, 1.0);

group_uniforms flame;
/** Какая доля дыма в пикселе должна быть горячей, чтобы пиксель светился цветом пламени. Меньше — огненный участок у сопла длиннее. */
uniform float hot_share : hint_range(0.0, 1.0, 0.01) = 0.5;
/** Горячий дым ракеты игрока: края. */
uniform vec4 rocket_flame_color : source_color = vec4(0.9686, 0.5882, 0.0902, 1.0);
/** Горячий дым ракеты игрока: густая сердцевина. */
uniform vec4 rocket_flame_core_color : source_color = vec4(0.9765, 0.7608, 0.1686, 1.0);
/** Горячий дым торпеды: края. */
uniform vec4 torpedo_flame_color : source_color = vec4(0.1882, 0.8824, 0.7255, 1.0);
/** Горячий дым торпеды: густая сердцевина. */
uniform vec4 torpedo_flame_core_color : source_color = vec4(0.5608, 0.9725, 0.8863, 1.0);

// Матрица Байера 4×4: у каждого пикселя в клетке 4×4 свой порог. Даёт ровную шахматку,
// какой в пиксель-арте рисуют переход между двумя цветами.
const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);


// Сдвиг порога для пикселя дыма, от -0.5 до 0.5.
float bayer(vec2 cell) {
	int index = int(mod(cell.x, 4.0)) + int(mod(cell.y, 4.0)) * 4;
	return (BAYER[index] + 0.5) / 16.0 - 0.5;
}


void fragment() {
	// Номер пикселя дыма, в который попал фрагмент экрана. Весь пиксель берёт плотность
	// из своего центра, поэтому гладкий буфер превращается в крупные квадраты.
	vec2 cell = floor(SCREEN_UV * canvas_size / pixel_size);
	vec2 uv = (cell + 0.5) * pixel_size / canvas_size;
	vec3 sum = textureLod(screen_texture, uv, 0.0).rgb;

	float shift = bayer(cell) * dither;
	float density = sum.r + shift;
	if (density < thin_threshold) {
		discard;
	}

	// Каналы g и b хранят плотность горячего дыма и дыма торпеды, а не долю: так клубы
	// складываются честно. Долю даёт деление на общую плотность. Нижняя граница делителя
	// нужна при нулевом thin_threshold, когда до сюда доходят и пустые пиксели.
	float total = max(sum.r, 0.001);
	float hot = sum.g / total;
	bool torpedo = sum.b / total > 0.5;
	bool dense = density >= dense_threshold;

	if (hot + shift >= hot_share) {
		if (torpedo) {
			COLOR = dense ? torpedo_flame_core_color : torpedo_flame_color;
		} else {
			COLOR = dense ? rocket_flame_core_color : rocket_flame_color;
		}
	} else if (dense) {
		COLOR = dense_color;
	} else if (density >= mid_threshold) {
		COLOR = mid_color;
	} else {
		COLOR = thin_color;
	}
}
