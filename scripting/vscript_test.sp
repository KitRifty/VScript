#include "include/vscript.inc"

#define TEST_ENTITY		0	// worldspawn
#define TEST_CLASSNAME	"worldspawn"

#define TEST_INTEGER	322
#define TEST_FLOAT		3.14159
#define TEST_CSTRING	"Message"

#define TEST_BOOLEAN	true
#define TEST_BOOLEAN_STR	"true"

#define TEST_VECTOR_0	1.0
#define TEST_VECTOR_1	2.0
#define TEST_VECTOR_2	3.0
#define TEST_VECTOR		{TEST_VECTOR_0, TEST_VECTOR_1, TEST_VECTOR_2}

public Plugin myinfo =
{
	name = "VScript Tests",
	author = "42",
	description = "Test and showcase stuffs for VScript plugin",
	version = "1.0.0",
	url = "https://github.com/FortyTwoFortyTwo/VScript",
};

public void OnMapStart()
{
	VScriptFunction pFunction;
	VScriptExecute hExecute;
	int iValue;
	char sBuffer[256];
	float vecResult[3];
	
	// Ensure that CBaseEntity is registered in L4D2
	SetVariantString("self.ValidateScriptScope()");
	AcceptEntityInput(TEST_ENTITY, "RunScriptCode");
	
	//Test this first, because of resetting g_pScriptVM
	pFunction = VScript_GetClassFunction("CBaseEntity", "BunchOfParams");
	if (!pFunction)
	{
		pFunction = VScript_GetClass("CBaseEntity").CreateFunction();
		pFunction.SetScriptName("BunchOfParams");
		pFunction.SetParam(1, FIELD_INTEGER);
		pFunction.SetParam(2, FIELD_FLOAT);
		pFunction.SetParam(3, FIELD_BOOLEAN);
		pFunction.SetParam(4, FIELD_VECTOR);
		
		pFunction.Return = FIELD_FLOAT;
		pFunction.SetFunctionEmpty();
		VScript_ResetScriptVM();
	}
	
	// TODO fix FIELD_CSTRING param causing return to go wrong
	
	// Create a detour for newly created function
	pFunction.CreateDetour().Enable(Hook_Pre, Detour_BunchOfParams);
	
	// Test with SDKCall
	float flValue = SDKCall(pFunction.CreateSDKCall(), TEST_ENTITY, TEST_INTEGER, TEST_FLOAT, TEST_BOOLEAN, TEST_VECTOR);
	AssertFloat(TEST_FLOAT, flValue);
	
	// Test again but with vscript
	// TODO fix returns
	Format(sBuffer, sizeof(sBuffer), "self.BunchOfParams(%d, %f, %s, Vector(%f, %f, %f))", TEST_INTEGER, TEST_FLOAT, TEST_BOOLEAN_STR, TEST_VECTOR_0, TEST_VECTOR_1, TEST_VECTOR_2);
	SetVariantString(sBuffer);
	AcceptEntityInput(TEST_ENTITY, "RunScriptCode");
	
	// Create AnotherRandomInt function that does the exact same as RandomInt
	pFunction = VScript_GetGlobalFunction("AnotherRandomInt");
	if (!pFunction)
	{
		pFunction = VScript_CreateFunction();
		pFunction.CopyFrom(VScript_GetGlobalFunction("RandomInt"));
		pFunction.SetScriptName("AnotherRandomInt");
		pFunction.Register();
	}
	
	DynamicDetour hDetour = pFunction.CreateDetour();
	hDetour.Enable(Hook_Post, Detour_RandomInt);
	iValue = SDKCall(pFunction.CreateSDKCall(), TEST_INTEGER, TEST_INTEGER);
	hDetour.Disable(Hook_Post, Detour_RandomInt);
	AssertInt(TEST_INTEGER, iValue);
	
	pFunction = VScript_GetGlobalFunction("ReturnString");
	if (!pFunction)
	{
		pFunction = VScript_CreateFunction();
		pFunction.SetScriptName("ReturnString");
		pFunction.Return = FIELD_CSTRING;
		pFunction.SetFunctionEmpty();
		pFunction.Register();
	}
	
	pFunction.CreateDetour().Enable(Hook_Pre, Detour_ReturnString);
	SDKCall(pFunction.CreateSDKCall(), sBuffer, sizeof(sBuffer));
	AssertString(TEST_CSTRING, sBuffer);
	
	// TODO fix this
	pFunction = VScript_GetGlobalFunction("ReturnVector");
	if (!pFunction)
	{
		pFunction = VScript_CreateFunction();
		pFunction.SetScriptName("ReturnVector");
		pFunction.Return = FIELD_VECTOR;
		pFunction.SetFunctionEmpty();
		pFunction.Register();
	}
	
	pFunction.CreateDetour().Enable(Hook_Pre, Detour_ReturnVector);
	SDKCall(pFunction.CreateSDKCall(), vecResult);
//	AssertVector(TEST_VECTOR, vecResult);	// TODO fix this
	
	// Test out instance function
	pFunction = VScript_GetClassFunction("CEntities", "FindByClassname");
	pFunction.CreateDetour().Enable(Hook_Pre, Detour_FindByClassname);
	
	HSCRIPT pEntities = HSCRIPT_RootTable.GetValue("Entities");
	iValue = SDKCall(pFunction.CreateSDKCall(), pEntities.Instance, 0, TEST_CLASSNAME);
	AssertInt(TEST_ENTITY, iValue);
	
	CheckFunctions(VScript_GetAllGlobalFunctions());
	
	ArrayList aList = VScript_GetAllClasses();
	int iLength = aList.Length;
	for (int i = 0; i < iLength; i++)
	{
		VScriptClass pClass = aList.Get(i);
		CheckFunctions(pClass.GetAllFunctions());
	}
	
	delete aList;
	
	// Test compile script with param and returns
	
	RunScript("function ReturnParam(param) { return param }");
	
	// Since were executing it with null scope, function is there
	hExecute = new VScriptExecute(HSCRIPT_RootTable.GetValue("ReturnParam"));
	
	hExecute.SetParam(1, FIELD_FLOAT, TEST_FLOAT);
	hExecute.Execute();
	AssertFloat(TEST_FLOAT, hExecute.ReturnValue);
	
	hExecute.SetParamString(1, FIELD_CSTRING, TEST_CSTRING);
	hExecute.Execute();
	hExecute.GetReturnString(sBuffer, sizeof(sBuffer));
	AssertString(TEST_CSTRING, sBuffer);
	
	hExecute.SetParamVector(1, FIELD_VECTOR, {1.0, 2.0, 3.0});
	hExecute.Execute();
	hExecute.GetReturnVector(vecResult);
	AssertVector(TEST_VECTOR, vecResult);
	
	delete hExecute;
	
	// Multiple params, test if ScriptVariant_t size is correct
	RunScript("function MoreParam(param1, param2, param3) { return param3 }");
	
	hExecute = new VScriptExecute(HSCRIPT_RootTable.GetValue("MoreParam"));
	hExecute.SetParam(1, FIELD_FLOAT, TEST_FLOAT);
	hExecute.SetParam(2, FIELD_BOOLEAN, TEST_BOOLEAN);
	hExecute.SetParam(3, FIELD_INTEGER, TEST_INTEGER);
	hExecute.Execute();
	AssertInt(TEST_INTEGER, hExecute.ReturnValue);
	
	// Test table stuffs
	HSCRIPT pTable = RunScript("return { thing = 322, empty = null, }");
	
	AssertInt(322, pTable.GetValue("thing"));
	AssertInt(1, pTable.ValueExists("empty"));
	AssertInt(1, pTable.IsValueNull("empty"));
	
	AssertInt(0, pTable.ValueExists(TEST_CSTRING));
	pTable.SetValue(TEST_CSTRING, FIELD_INTEGER, TEST_INTEGER);
	AssertInt(1, pTable.ValueExists(TEST_CSTRING));
	AssertInt(FIELD_INTEGER, pTable.GetValueField(TEST_CSTRING));
	
	AssertInt(0, pTable.IsValueNull(TEST_CSTRING));
	pTable.SetValueNull(TEST_CSTRING);
	AssertInt(1, pTable.IsValueNull(TEST_CSTRING));
	
	pTable.ClearValue(TEST_CSTRING);
	AssertInt(0, pTable.ValueExists(TEST_CSTRING));
	
	pTable.Release();
	
	PrintToServer("All tests passed!");
}

any RunScript(const char[] sScript)
{
	HSCRIPT pCompile = VScript_CompileScript(sScript);
	VScriptExecute hExecute = new VScriptExecute(pCompile);
	hExecute.Execute();
	any nReturn = hExecute.ReturnValue;
	
	delete hExecute;
	
	pCompile.ReleaseScript();
	return nReturn;
}

void CheckFunctions(ArrayList aList)
{
	// Check that all function params don't have FIELD_VOID
	int iLength = aList.Length;
	for (int i = 0; i < iLength; i++)
	{
		VScriptFunction pFunction = aList.Get(i);
		int iParamCount = pFunction.ParamCount;
		for (int j = 1; j <= iParamCount; j++)
		{
			if (pFunction.GetParam(j) != FIELD_VOID)
				continue;
			
			char sName[256];
			pFunction.GetScriptName(sName, sizeof(sName));
			ThrowError("Found FIELD_VOID in function '%s' at param '%d'", sName, j);
		}
	}
	
	delete aList;
}

public MRESReturn Detour_RandomInt(DHookReturn hReturn, DHookParam hParam)
{
	AssertInt(TEST_INTEGER, hParam.Get(1));
	AssertInt(TEST_INTEGER, hParam.Get(2));
	return MRES_Ignored;
}

public MRESReturn Detour_BunchOfParams(int iEntity, DHookReturn hReturn, DHookParam hParam)
{
	AssertInt(TEST_INTEGER, hParam.Get(1));
	AssertFloat(TEST_FLOAT, hParam.Get(2));
	AssertInt(TEST_BOOLEAN, hParam.Get(3));
	
	float vecBuffer[3];
	for (int i = 0; i < sizeof(vecBuffer); i++)
		vecBuffer[i] = hParam.GetObjectVar(4, i * 4, ObjectValueType_Float);
	
	AssertVector(TEST_VECTOR, vecBuffer);
	
	hReturn.Value = TEST_FLOAT;	// TODO fix this, dont always work
	return MRES_Supercede;
}

public MRESReturn Detour_ReturnString(DHookReturn hReturn)
{
	hReturn.SetString(TEST_CSTRING);
	return MRES_Supercede;
}

public MRESReturn Detour_ReturnVector(DHookReturn hReturn)
{
	hReturn.SetVector(TEST_VECTOR);
	return MRES_Supercede;
}

public MRESReturn Detour_FindByClassname(Address pThis, DHookReturn hReturn, DHookParam hParam)
{
	AssertInt(0, hParam.Get(1));
	
	char sBuffer[256];
	hParam.GetString(2, sBuffer, sizeof(sBuffer));
	AssertString(TEST_CLASSNAME, sBuffer);
	return MRES_Ignored;
}

void AssertInt(any nValue1, any nValue2)
{
	if (nValue1 != nValue2)
		ThrowError("Expected int '%d', found '%d'", nValue1, nValue2);
}

void AssertFloat(any nValue1, any nValue2)
{
	if (nValue1 != nValue2)
		ThrowError("Expected float '%f', found '%f'", nValue1, nValue2);
}

void AssertString(const char[] sValue1, const char[] sValue2)
{
	if (!StrEqual(sValue1, sValue2))
		ThrowError("Expected string '%s', found '%s'", sValue1, sValue2);
}

void AssertVector(const float vecValue1[3], const float vecValue2[3])
{
	for (int i = 0; i < 3; i++)
		if (vecValue1[i] != vecValue2[i])
			ThrowError("Expected vector '{%0.2f, %0.2f, %0.2f}', found '{%0.2f, %0.2f, %0.2f}'", vecValue1[0], vecValue1[1], vecValue1[2], vecValue2[0], vecValue2[1], vecValue2[2]);
}
