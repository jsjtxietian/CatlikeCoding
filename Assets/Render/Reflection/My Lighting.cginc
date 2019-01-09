#if !defined(MY_LIGHTING_INCLUDED)
#define MY_LIGHTING_INCLUDED

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

float4 _Tint;
sampler2D _MainTex;
float4 _MainTex_ST;

float _Metallic;
float _Smoothness;

struct VertexData {
    float4 vertex  : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

struct Interpolators {
    float4 pos  : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float3 worldPos : TEXCOORD2;

    // #if defined(SHADOWS_SCREEN)
	// 	float4 shadowCoordinates : TEXCOORD5;
	// #endif
    SHADOW_COORDS(5)

    #if defined(VERTEXLIGHT_ON)
		float3 vertexLightColor : TEXCOORD3;
	#endif
};

void ComputeVertexLightColor (inout Interpolators i) {
    #if defined(VERTEXLIGHT_ON)
		i.vertexLightColor = Shade4PointLights(
			unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
			unity_LightColor[0].rgb, unity_LightColor[1].rgb,
			unity_LightColor[2].rgb, unity_LightColor[3].rgb,
			unity_4LightAtten0, i.worldPos, i.normal
		);
	#endif
}

Interpolators MyVertexProgram (VertexData v) {
    Interpolators i;
    i.pos = UnityObjectToClipPos(v.vertex);
    i.worldPos = mul(unity_ObjectToWorld, v.vertex);
    i.normal = UnityObjectToWorldNormal(v.normal);
    i.uv = TRANSFORM_TEX(v.uv, _MainTex);

    // #if defined(SHADOWS_SCREEN)
	// 	// i.shadowCoordinates.xy =
	// 	// 	(float2(i.position.x, -i.position.y) + i.position.w) * 0.5 ;
	// 	// i.shadowCoordinates.zw = i.position.zw;
    //     i.shadowCoordinates = ComputeScreenPos(i.position);
	// #endif
    TRANSFER_SHADOW(i);

    ComputeVertexLightColor(i);
    return i;
}

UnityLight CreateLight (Interpolators i) {
	UnityLight light;

    #if defined(POINT) || defined(SPOT) || defined(POINT_CPPKIE)
		light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
	#else
		light.dir = _WorldSpaceLightPos0.xyz;
	#endif

    // #if defined(SHADOWS_SCREEN)
	// 	// float attenuation = tex2D(
    //     //     _ShadowMapTexture, 
    //     //     i.shadowCoordinates.xy / i.shadowCoordinates.w);
    //     float attenuation = SHADOW_ATTENUATION(i);
	// #else
    UNITY_LIGHT_ATTENUATION(attenuation, i, i.worldPos);
	// #endif

	light.color = _LightColor0.rgb * attenuation;
	light.ndotl = DotClamped(i.normal, light.dir);
	return light;
}

float3 BoxProjection (
	float3 direction, float3 position,
	float4 cubemapPosition, float3 boxMin, float3 boxMax
) {
	#if UNITY_SPECCUBE_BOX_PROJECTION
		UNITY_BRANCH
		if (cubemapPosition.w > 0) {
			float3 factors =
				((direction > 0 ? boxMax : boxMin) - position) / direction;
			float scalar = min(min(factors.x, factors.y), factors.z);
			direction = direction * scalar + (position - cubemapPosition);
		}
	#endif
	return direction;
}

UnityIndirect CreateIndirectLight (Interpolators i , float3 viewDir) {
	UnityIndirect indirectLight;
	indirectLight.diffuse = 0;
	indirectLight.specular = 0;

	#if defined(VERTEXLIGHT_ON)
		indirectLight.diffuse = i.vertexLightColor;
	#endif

    #if defined(FORWARD_BASE_PASS)
		indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
        float3 reflectionDir = reflect(-viewDir, i.normal);
        // float roughness = 1 - _Smoothness;
        // roughness *= 1.7 - 0.7 * roughness;
        // float4 envSample = UNITY_SAMPLE_TEXCUBE_LOD(
		// 	unity_SpecCube0, reflectionDir, roughness * UNITY_SPECCUBE_LOD_STEPS
		// );
        // indirectLight.specular = DecodeHDR(envSample, unity_SpecCube0_HDR);
        Unity_GlossyEnvironmentData envData;
		envData.roughness = 1 - _Smoothness;
		envData.reflUVW = BoxProjection(
			reflectionDir, i.worldPos,
			unity_SpecCube0_ProbePosition,
			unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax
		);
		float3 probe0 = Unity_GlossyEnvironment(
			UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
		);

        envData.reflUVW = BoxProjection(
			reflectionDir, i.worldPos,
			unity_SpecCube1_ProbePosition,
			unity_SpecCube1_BoxMin, unity_SpecCube1_BoxMax
		);

        #if UNITY_SPECCUBE_BLENDING
            float interpolator = unity_SpecCube0_BoxMin.w;

            UNITY_BRANCH
            if (interpolator < 0.99999) {
                float3 probe1 = Unity_GlossyEnvironment(
                    UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1, unity_SpecCube0),
                    unity_SpecCube0_HDR, envData
                );
                indirectLight.specular = lerp(probe1, probe0, interpolator);
            }
            else {
                indirectLight.specular = probe0;
            }

        #else
			indirectLight.specular = probe0;
		#endif

	#endif
    
	return indirectLight;
}

float4 MyFragmentProgram (Interpolators i) : SV_TARGET {
    i.normal = normalize(i.normal);
    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);

    float3 albedo = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;

    float3 specularTint;
    float oneMinusReflectivity;
    albedo = DiffuseAndSpecularFromMetallic(
        albedo, _Metallic, specularTint, oneMinusReflectivity
    );

    return UNITY_BRDF_PBS(
        albedo, specularTint,
        oneMinusReflectivity, _Smoothness,
        i.normal, viewDir,
        CreateLight(i), CreateIndirectLight(i,viewDir)
        );
}

#endif