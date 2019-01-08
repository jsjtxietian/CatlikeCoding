// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/Lighting Shader Bumpiness" {

	Properties {
		_Tint ("Tint", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" {}
		[NoScaleOffset] _NormalMap ("Normals", 2D) = "bump" {}
		_BumpScale ("Bump Scale", Float) = 1
		[Gamma] _Metallic ("Metallic", Range(0, 1)) = 0
		_Smoothness ("Smoothness", Range(0, 1)) = 0.1
		_DetailTex ("Detail Texture", 2D) = "gray" {}
		[NoScaleOffset] _DetailNormalMap ("Detail Normals", 2D) = "bump" {}
		_DetailBumpScale ("Detail Bump Scale", Float) = 1
	}

	CGINCLUDE
	#define BINORMAL_PER_FRAGMENT
	ENDCG

	SubShader {

		Pass {
			Tags {
				"LightMode" = "ForwardBase"
			}

			CGPROGRAM

			#pragma vertex MyVertexProgram
			#pragma fragment MyFragmentProgram
            #pragma target 3.0

			#include "UnityPBSLighting.cginc"

			float4 _Tint;
			sampler2D _MainTex, _DetailTex;
			float4 _MainTex_ST, _DetailTex_ST;
			sampler2D _NormalMap, _DetailNormalMap;
			float _BumpScale, _DetailBumpScale;
			// sampler2D _HeightMap;
			// float4 _HeightMap_TexelSize;

			float _Metallic;
			float _Smoothness;

			struct VertexData {
				float4 position : POSITION;
				float3 normal : NORMAL;
				float2 uv : TEXCOORD0;
				float4 tangent : TANGENT;
			};

			struct Interpolators {
				float4 position : SV_POSITION;
				float4 uv : TEXCOORD0;
				float3 normal : TEXCOORD1;
				#if defined(BINORMAL_PER_FRAGMENT)
					float4 tangent : TEXCOORD2;
				#else
					float3 tangent : TEXCOORD2;
					float3 binormal : TEXCOORD3;
				#endif
				float3 worldPos : TEXCOORD4;
			};

			float3 CreateBinormal (float3 normal, float3 tangent, float binormalSign) {
				return cross(normal, tangent.xyz) *
					(binormalSign * unity_WorldTransformParams.w);
			}

			Interpolators MyVertexProgram (VertexData v) {
				Interpolators i;
				i.position = UnityObjectToClipPos(v.position);
				i.worldPos = mul(unity_ObjectToWorld, v.position);
				i.normal = UnityObjectToWorldNormal(v.normal);

				#if defined(BINORMAL_PER_FRAGMENT)
					i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
				#else
					i.tangent = UnityObjectToWorldDir(v.tangent.xyz);
					i.binormal = CreateBinormal(i.normal, i.tangent, v.tangent.w);
				#endif

				i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
				i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);
				return i;
			}




			void InitializeFragmentNormal(inout Interpolators i) {
				float3 mainNormal = UnpackScaleNormal(tex2D(_NormalMap, i.uv.xy), _BumpScale);
				float3 detailNormal = UnpackScaleNormal(tex2D(_DetailNormalMap, i.uv.zw), _DetailBumpScale);

				float3 tangentSpaceNormal = BlendNormals(mainNormal, detailNormal);

				#if defined(BINORMAL_PER_FRAGMENT)
					float3 binormal = CreateBinormal(i.normal, i.tangent.xyz, i.tangent.w);
				#else
					float3 binormal = i.binormal;
				#endif
	
				i.normal = normalize(
					tangentSpaceNormal.x * i.tangent +
					tangentSpaceNormal.y * binormal +
					tangentSpaceNormal.z * i.normal);
			}

			float4 MyFragmentProgram (Interpolators i) : SV_TARGET {
				
				InitializeFragmentNormal(i);
				
				float3 lightDir = _WorldSpaceLightPos0.xyz;
				float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);

				float3 lightColor = _LightColor0.rgb;
				float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Tint.rgb;
				albedo *= tex2D(_DetailTex, i.uv.zw) * unity_ColorSpaceDouble;

				float3 specularTint;
				float oneMinusReflectivity;
				albedo = DiffuseAndSpecularFromMetallic(
					albedo, _Metallic, specularTint, oneMinusReflectivity
				);

                UnityLight light;
				light.color = lightColor;
				light.dir = lightDir;
				light.ndotl = DotClamped(i.normal, lightDir);
				UnityIndirect indirectLight;
				indirectLight.diffuse = 0;
				indirectLight.specular = 0;

				return  UNITY_BRDF_PBS(
                    albedo, specularTint,
                    oneMinusReflectivity, _Smoothness,
                    i.normal, viewDir,
                    light, indirectLight
                    );
			}

			ENDCG
		}
	}
}