namespace BadExamples;

public static class CompileFail
{
    public static int Broken()
    {
        int n = "not a number";
        return n;
    }
}
